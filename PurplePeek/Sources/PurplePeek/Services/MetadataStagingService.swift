import Foundation

/// Embeds title/caption/keywords into a **staged copy** of a photo via `exiftool` so the
/// Photos library ingests them on import (PhotoKit can't write these fields directly).
/// Only photos are staged — exiftool's XMP/IPTC write into images is reliable, whereas
/// video-container metadata is not. If exiftool is missing or there's nothing to embed,
/// callers import the original instead.
enum MetadataStagingService {

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

    /// Copy `original` into the staging directory and embed `metadata` with exiftool.
    /// Returns the staged file URL (the caller imports it, then deletes it).
    static func stage(original: URL, metadata: Metadata, exiftoolPath: String) throws -> URL {
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

        var args = ["-overwrite_original", "-codedcharacterset=utf8", "-charset", "iptc=UTF8"]
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
        args.append(staged.path)

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
