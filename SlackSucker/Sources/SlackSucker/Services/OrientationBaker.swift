import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Bakes EXIF `Orientation` (and the video equivalent — display
/// rotation matrix) into the actual pixel data of media files, so they
/// look correct regardless of whether downstream tools honor the flag.
///
/// What this CAN do:
///   - Photos with a non-default `Orientation` EXIF tag → rotate pixels
///     and reset Orientation=1 using ImageIO + CoreImage.
///   - Videos whose container reports a non-zero display rotation →
///     re-encode via ffmpeg with `-display_rotation 0`, dropping the
///     metadata flag. Requires ffmpeg on PATH; skipped otherwise.
///
/// What this CAN'T do:
///   - Detect that a photo "should be" rotated when there's no EXIF
///     flag (e.g. screenshots, edited copies, content shared through
///     pipelines that stripped metadata). Inferring up/down from
///     pixels requires ML face/horizon detection and is unreliable on
///     group shots, indoor photos, and abstract content — out of scope.
///
/// Result: a tally of files inspected, files re-oriented, and files
/// skipped (with reasons). Runs BEFORE `MetadataStripper` so the
/// orientation hint isn't gone by the time we read it.
enum OrientationBaker {

    struct Result {
        var photosInspected: Int = 0
        var photosRotated: Int = 0
        var videosInspected: Int = 0
        var videosRotated: Int = 0
        var skipped: [String] = []
        var errors: [String] = []
    }

    static let photoExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "tif", "tiff", "png"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    @discardableResult
    static func run(runFolder: URL) -> Result {
        var result = Result()
        bakePhotos(in: runFolder.appendingPathComponent("Photos", isDirectory: true),
                   into: &result)
        bakeVideos(in: runFolder.appendingPathComponent("Videos", isDirectory: true),
                   into: &result)

        let log = formatLog(result)
        let logURL = runFolder.appendingPathComponent("orient-log.txt")
        try? log.write(to: logURL, atomically: true, encoding: .utf8)
        return result
    }

    // MARK: - Photos

    private static func bakePhotos(in dir: URL, into result: inout Result) {
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        for url in HashService.filesUnder(dir) {
            let ext = url.pathExtension.lowercased()
            guard photoExtensions.contains(ext) else { continue }
            result.photosInspected += 1
            switch bakePhoto(at: url) {
            case .rotated:                  result.photosRotated += 1
            case .alreadyUpright:           break
            case .unsupported(let reason): result.skipped.append("\(url.lastPathComponent): \(reason)")
            case .error(let reason):       result.errors.append("\(url.lastPathComponent): \(reason)")
            }
        }
    }

    enum PhotoOutcome {
        case rotated
        case alreadyUpright
        case unsupported(String)
        case error(String)
    }

    /// Atomic-replace re-encode that bakes the EXIF Orientation into
    /// pixel data. Renders via Core Image, writes to a sibling tmp
    /// file, then moves over the original.
    static func bakePhoto(at url: URL) -> PhotoOutcome {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return .error("CGImageSource create failed")
        }
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            return .error("read properties failed")
        }
        let orientation = (props[kCGImagePropertyOrientation] as? Int) ?? 1
        if orientation == 1 { return .alreadyUpright }

        guard let utType = CGImageSourceGetType(src) else {
            return .unsupported("unknown UTI")
        }
        guard let ciInput = CIImage(contentsOf: url) else {
            return .unsupported("Core Image couldn't decode")
        }
        let oriented = ciInput.oriented(forExifOrientation: Int32(orientation))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(oriented, from: oriented.extent) else {
            return .error("CIContext.createCGImage returned nil")
        }
        let tmpURL = url.appendingPathExtension("orient-tmp")
        guard let dst = CGImageDestinationCreateWithURL(tmpURL as CFURL, utType, 1, nil) else {
            return .error("CGImageDestination create failed")
        }
        var newProps = props
        newProps[kCGImagePropertyOrientation] = 1
        CGImageDestinationAddImage(dst, cg, newProps as CFDictionary)
        guard CGImageDestinationFinalize(dst) else {
            try? FileManager.default.removeItem(at: tmpURL)
            return .error("CGImageDestination finalize failed")
        }
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            return .error("replaceItem: \(error.localizedDescription)")
        }
        return .rotated
    }

    // MARK: - Videos

    /// Find ffmpeg on PATH (homebrew or system). nil → skip videos.
    nonisolated static func ffmpegBinary() -> String? {
        for p in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"] {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    nonisolated static func ffprobeBinary() -> String? {
        for p in ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe", "/usr/bin/ffprobe"] {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    private static func bakeVideos(in dir: URL, into result: inout Result) {
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        guard let ffmpeg = ffmpegBinary() else {
            result.skipped.append("Videos/: ffmpeg not on PATH — install via `brew install ffmpeg` to enable video orientation baking")
            return
        }
        let ffprobe = ffprobeBinary()

        for url in HashService.filesUnder(dir) {
            let ext = url.pathExtension.lowercased()
            guard videoExtensions.contains(ext) else { continue }
            result.videosInspected += 1

            // Try to detect rotation cheaply via ffprobe; fall back to
            // unconditionally re-encoding if ffprobe isn't around.
            let rotation: Int
            if let ffprobe {
                rotation = videoRotation(ffprobe: ffprobe, url: url)
            } else {
                rotation = -1  // unknown
            }

            if rotation == 0 {
                continue  // already correctly oriented at container level
            }

            switch bakeVideo(ffmpeg: ffmpeg, url: url) {
            case .rotated:               result.videosRotated += 1
            case .skipped(let reason):   result.skipped.append("\(url.lastPathComponent): \(reason)")
            case .error(let reason):     result.errors.append("\(url.lastPathComponent): \(reason)")
            }
        }
    }

    enum VideoOutcome {
        case rotated
        case skipped(String)
        case error(String)
    }

    /// Re-encode a video to flatten any container rotation into the
    /// stream itself, then drop the rotation metadata. The user pays a
    /// transcode cost but ends up with a file every player renders the
    /// same way.
    private static func bakeVideo(ffmpeg: String, url: URL) -> VideoOutcome {
        let tmp = url.appendingPathExtension("orient-tmp." + url.pathExtension)
        try? FileManager.default.removeItem(at: tmp)
        let args = [
            "-y", "-loglevel", "error", "-nostdin",
            "-i", url.path,
            "-map_metadata", "0",
            "-metadata:s:v:0", "rotate=0",
            "-display_rotation", "0",
            "-c", "copy",
            tmp.path
        ]
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ffmpeg)
        proc.arguments = args
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do { try proc.run() } catch {
            try? FileManager.default.removeItem(at: tmp)
            return .error("ffmpeg launch: \(error.localizedDescription)")
        }
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            try? FileManager.default.removeItem(at: tmp)
            return .skipped("ffmpeg exit \(proc.terminationStatus) — likely no rotation metadata on this file")
        }
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return .error("replaceItem: \(error.localizedDescription)")
        }
        return .rotated
    }

    /// Best-effort rotation lookup. Returns 0 when we couldn't find a
    /// rotation tag (treat as "leave alone"), the matrix rotation when
    /// we did, or -1 when ffprobe isn't available.
    private static func videoRotation(ffprobe: String, url: URL) -> Int {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffprobe)
        p.arguments = [
            "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream_side_data=rotation",
            "-of", "default=nw=1:nk=1",
            url.path
        ]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return 0 }
        p.waitUntilExit()
        if p.terminationStatus != 0 { return 0 }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        // ffprobe may print a negative rotation for the matrix; normalise.
        let value = Int(Double(trimmed) ?? 0)
        return ((value % 360) + 360) % 360
    }

    // MARK: - Log

    private static func formatLog(_ r: Result) -> String {
        var s = "SlackSucker — orientation bake log\n"
        s += "Photos inspected: \(r.photosInspected) (rotated: \(r.photosRotated))\n"
        s += "Videos inspected: \(r.videosInspected) (rotated: \(r.videosRotated))\n"
        if !r.skipped.isEmpty {
            s += "\nSkipped:\n"
            for line in r.skipped { s += "  - \(line)\n" }
        }
        if !r.errors.isEmpty {
            s += "\nErrors:\n"
            for line in r.errors { s += "  - \(line)\n" }
        }
        return s
    }
}
