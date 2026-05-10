import Foundation

/// Locates a system-installed `ffmpeg` + `ffprobe` pair so the video
/// fingerprinter can fall back to FFmpeg for formats AVFoundation can't
/// decode (MKV, AVI, WMV, WebM, etc.).
///
/// We deliberately do NOT bundle FFmpeg: it's GPL-licensed and bundling it
/// would force PurpleDedup under GPL too. Probing for a user-installed copy
/// (Homebrew, MacPorts, manual) keeps the trade-off the user's: no FFmpeg →
/// no support for those formats; install FFmpeg → support appears
/// automatically next launch.
public struct FFmpegProbe: Sendable {

    /// Concrete pointer to a working FFmpeg installation.
    public struct Probe: Sendable, Hashable {
        public let ffmpegURL: URL
        public let ffprobeURL: URL
        /// First line of `ffmpeg -version` (e.g. "ffmpeg version 6.0").
        public let versionLine: String
    }

    /// Search order: explicit env var → known Homebrew/MacPorts paths → PATH
    /// via `/usr/bin/env`. Returns nil if no matching pair is found OR either
    /// binary fails to execute (corrupt install, permission denied).
    public static func find() -> Probe? {
        // 1. FFMPEG_PATH env var. Useful when developing against a non-system
        // build, or when CI sets it explicitly.
        if let envPath = ProcessInfo.processInfo.environment["FFMPEG_PATH"],
           let probe = makeProbe(ffmpegPath: envPath) {
            return probe
        }

        // 2. Common install locations. Homebrew's prefix differs between
        // Apple Silicon (/opt/homebrew) and Intel (/usr/local), and MacPorts
        // installs to /opt/local. Listing them avoids relying on the parent
        // process's PATH (which is sometimes empty in launchd-spawned apps).
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/opt/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
        ]
        for path in candidates {
            if let probe = makeProbe(ffmpegPath: path) { return probe }
        }

        // 3. PATH search via `which`. Last resort because PATH inside a
        // GUI-launched .app rarely matches the user's shell PATH (Finder
        // launches inherit the launchd defaults, not ~/.zshrc additions).
        if let pathFromShell = whichOnPath("ffmpeg"),
           let probe = makeProbe(ffmpegPath: pathFromShell) {
            return probe
        }

        return nil
    }

    private static func makeProbe(ffmpegPath: String) -> Probe? {
        guard FileManager.default.isExecutableFile(atPath: ffmpegPath) else { return nil }
        // ffprobe lives next to ffmpeg in every distribution we care about.
        // Replace the trailing `ffmpeg` with `ffprobe` rather than guessing
        // the directory, so we work for paths like `/usr/local/bin/ffmpeg`
        // and the env-var override case.
        let ffprobePath: String = {
            if ffmpegPath.hasSuffix("/ffmpeg") {
                return String(ffmpegPath.dropLast("ffmpeg".count)) + "ffprobe"
            }
            // Fallback: same directory, name `ffprobe`.
            let dir = (ffmpegPath as NSString).deletingLastPathComponent
            return (dir as NSString).appendingPathComponent("ffprobe")
        }()
        guard FileManager.default.isExecutableFile(atPath: ffprobePath) else { return nil }
        guard let version = readVersionLine(ffmpegPath: ffmpegPath) else { return nil }
        return Probe(
            ffmpegURL: URL(fileURLWithPath: ffmpegPath),
            ffprobeURL: URL(fileURLWithPath: ffprobePath),
            versionLine: version
        )
    }

    private static func readVersionLine(ffmpegPath: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpegPath)
        p.arguments = ["-hide_banner", "-version"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe() // discard
        do {
            try p.run()
        } catch {
            return nil
        }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let str = String(data: data, encoding: .utf8) ?? ""
        return str.split(separator: "\n").first.map(String.init)
    }

    private static func whichOnPath(_ name: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["which", name]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
        } catch {
            return nil
        }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let trimmed = (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
