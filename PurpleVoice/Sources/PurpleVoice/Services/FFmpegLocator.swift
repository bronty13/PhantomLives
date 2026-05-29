import Foundation

/// Finds the system `ffmpeg` binary. GUI apps launched from Finder
/// inherit a stripped-down PATH that often excludes `/opt/homebrew/bin`
/// and `/usr/local/bin`, so we cannot rely on a bare `PATH` lookup —
/// the search order below explicitly includes both Homebrew prefixes.
///
/// Returns `nil` if no executable ffmpeg is found; the UI shows a
/// "missing ffmpeg" pane in that case rather than failing silently.
enum FFmpegLocator {

    /// Search locations in priority order:
    /// 1. `PURPLE_VOICE_FFMPEG` env var (escape hatch for testing)
    /// 2. `/opt/homebrew/bin/ffmpeg` (Apple Silicon Homebrew)
    /// 3. `/usr/local/bin/ffmpeg` (Intel Homebrew / manual install)
    /// 4. `/opt/local/bin/ffmpeg` (MacPorts)
    /// 5. `PATH` lookup via `/usr/bin/which` (covers custom locations)
    static func find(environment: [String: String]? = nil,
                     fileManager: FileManager = .default) -> URL? {
        let env = environment ?? ProcessInfo.processInfo.environment

        if let override = env["PURPLE_VOICE_FFMPEG"],
           !override.isEmpty,
           fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        let knownPaths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/opt/local/bin/ffmpeg"
        ]
        for p in knownPaths where fileManager.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }

        if let viaWhich = whichLookup(name: "ffmpeg", env: env) {
            return viaWhich
        }
        return nil
    }

    private static func whichLookup(name: String, env: [String: String]) -> URL? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        p.arguments = [name]
        // Hand /usr/bin/which an explicit PATH that includes the
        // Homebrew prefixes; Finder-launched apps don't get them by
        // default. Whatever PATH the env carries goes first so a user
        // override still wins.
        var augmented = env
        let inheritedPath = env["PATH"] ?? ""
        augmented["PATH"] = "\(inheritedPath):/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:/usr/bin:/bin"
        p.environment = augmented
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let raw = String(data: data, encoding: .utf8) ?? ""
            let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : URL(fileURLWithPath: path)
        } catch {
            return nil
        }
    }
}
