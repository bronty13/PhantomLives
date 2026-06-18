import Foundation

/// Embeds title/caption/keywords into a **staged copy** of a photo or video via `exiftool`
/// so the Photos library ingests them on import (PhotoKit can't write these fields directly).
///
/// Photos use the XMP/IPTC tags Photos reads from still images; videos use the QuickTime
/// **`Keys:` group** (`Keys:Title` / `Keys:Description` / `Keys:Keywords`), which Photos
/// ingests natively on import — verified 2026-06-18: a clip tagged this way imports with the
/// right Title/Caption and the comma-joined keyword string split into individual keywords.
/// (This replaced an earlier AppleScript "control Photos" path, removing that TCC prompt and
/// the apple-events entitlement entirely — see `docs/tcc-prompt-research-spike.md`.)
///
/// If exiftool is missing or there's nothing to embed, callers import the original instead.
enum MetadataStagingService {

    /// What kind of container we're embedding into — selects the tag set exiftool writes.
    enum Kind: Sendable { case photo, video }

    struct Metadata: Sendable {
        var title: String?
        var caption: String?
        var keywords: [String]

        var isEmpty: Bool {
            (title?.isEmpty ?? true) && (caption?.isEmpty ?? true) && keywords.isEmpty
        }
    }

    enum StagingError: Error, LocalizedError {
        case copyFailed(String)
        case exiftoolFailed(Int32, String)
        var errorDescription: String? {
            switch self {
            case .copyFailed(let s): return "Couldn't stage a copy: \(s)"
            case .exiftoolFailed(let c, let e): return "exiftool exited \(c): \(e)"
            }
        }
    }

    static var stagingDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("PurplePeek/staging", isDirectory: true)
    }

    /// Locate exiftool once (callers cache the result).
    static func locateExiftool() -> String? {
        for path in ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Fall back to `which` via the login shell PATH.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["which", "exiftool"]
        let pipe = Pipe(); proc.standardOutput = pipe
        try? proc.run(); proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (out?.isEmpty == false) ? out : nil
    }

    /// Build the exiftool argument list for embedding `metadata` of the given `kind` into
    /// `path`. Split out from `stage` so the tag set is unit-testable without spawning
    /// exiftool or touching the filesystem.
    ///
    /// Photos read different tags from images vs. movies, so the sets diverge:
    /// - **Photos** — `XMP:Title`/`IPTC:ObjectName` (title), `IPTC:Caption-Abstract` +
    ///   `XMP-dc:Description` + `EXIF:ImageDescription` (caption), and `IPTC:Keywords` +
    ///   `XMP-dc:Subject` (list tags — one `-TAG=` per keyword *accumulates*).
    /// - **Videos** — the QuickTime `Keys:` group. `Keys:Keywords` is **not** a list tag
    ///   (repeated `-Keys:Keywords=` would overwrite), so keywords go in as a single
    ///   comma-joined string; Photos splits it back into individual keywords on import.
    ///   `Keys:DisplayName` is deliberately **not** set — it would override `Keys:Title`.
    static func exiftoolArgs(kind: Kind, metadata: Metadata, path: String) -> [String] {
        var args = ["-overwrite_original", "-codedcharacterset=utf8", "-charset", "iptc=UTF8"]
        switch kind {
        case .photo:
            if let title = metadata.title, !title.isEmpty {
                args.append("-XMP:Title=\(title)")
                args.append("-IPTC:ObjectName=\(title)")
            }
            if let caption = metadata.caption, !caption.isEmpty {
                args.append("-IPTC:Caption-Abstract=\(caption)")
                args.append("-XMP-dc:Description=\(caption)")
                args.append("-EXIF:ImageDescription=\(caption)")
            }
            for kw in metadata.keywords where !kw.isEmpty {
                args.append("-IPTC:Keywords=\(kw)")
                args.append("-XMP-dc:Subject=\(kw)")
            }
        case .video:
            if let title = metadata.title, !title.isEmpty {
                args.append("-Keys:Title=\(title)")
            }
            if let caption = metadata.caption, !caption.isEmpty {
                args.append("-Keys:Description=\(caption)")
            }
            let kws = metadata.keywords.filter { !$0.isEmpty }
            if !kws.isEmpty {
                args.append("-Keys:Keywords=\(kws.joined(separator: ","))")
            }
        }
        args.append(path)
        return args
    }

    /// Copy `original` into the staging directory and embed `metadata` with exiftool.
    /// Returns the staged file URL (the caller imports it, then deletes it). `kind` selects
    /// the tag set (photos use XMP/IPTC; videos use the QuickTime `Keys:` group).
    static func stage(original: URL, metadata: Metadata, exiftoolPath: String, kind: Kind = .photo) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let staged = stagingDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(original.pathExtension)
        do {
            try fm.copyItem(at: original, to: staged)
        } catch {
            throw StagingError.copyFailed(error.localizedDescription)
        }

        let args = exiftoolArgs(kind: kind, metadata: metadata, path: staged.path)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exiftoolPath)
        proc.arguments = args
        let errPipe = Pipe(); proc.standardError = errPipe
        let outPipe = Pipe(); proc.standardOutput = outPipe
        do {
            try proc.run()
        } catch {
            try? fm.removeItem(at: staged)
            throw StagingError.copyFailed(error.localizedDescription)
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            try? fm.removeItem(at: staged)
            throw StagingError.exiftoolFailed(proc.terminationStatus, err)
        }
        return staged
    }
}
