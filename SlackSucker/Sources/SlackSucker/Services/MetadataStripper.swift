import Foundation

/// Strips EXIF / IPTC / XMP metadata from media files in-place using
/// the `exiftool` binary on PATH. Photos lose camera model, GPS, EXIF
/// timestamps, comments, etc.; videos lose author / creation tags.
///
/// Requires `exiftool` on PATH (`brew install exiftool`). If absent,
/// the service no-ops and returns a single skip reason so the runner
/// can surface "metadata strip skipped — exiftool not installed" in
/// the live log instead of silently doing nothing.
///
/// Order: must run AFTER `OrientationBaker` — stripping all metadata
/// also wipes the EXIF Orientation tag, which means anything that
/// hadn't been baked first will look rotated after the strip.
///
/// Destructive: passes `-overwrite_original` to exiftool. The
/// slackdump SQLite still has the original message timestamps + user
/// metadata, so the run-folder still carries the provenance trail.
enum MetadataStripper {

    struct Result {
        var filesProcessed: Int = 0
        var filesChanged: Int = 0
        var errors: [String] = []
        var skipped: [String] = []
    }

    static let photoExtensions = OrientationBaker.photoExtensions
    static let videoExtensions = OrientationBaker.videoExtensions

    nonisolated static func exiftoolBinary() -> String? {
        for p in ["/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool", "/usr/bin/exiftool"] {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    @discardableResult
    static func run(runFolder: URL) -> Result {
        var result = Result()
        guard let exiftool = exiftoolBinary() else {
            result.skipped.append("exiftool not on PATH — install via `brew install exiftool` to enable metadata stripping")
            writeLog(result, runFolder: runFolder)
            return result
        }

        // Target Photos/ + Videos/ — Audio/ and Other/ aren't worth
        // touching (transcripts, PDFs, archives don't carry the same
        // privacy-sensitive tags).
        let dirs = [
            runFolder.appendingPathComponent("Photos", isDirectory: true),
            runFolder.appendingPathComponent("Videos", isDirectory: true)
        ]
        var allFiles: [URL] = []
        for dir in dirs where FileManager.default.fileExists(atPath: dir.path) {
            allFiles.append(contentsOf: HashService.filesUnder(dir))
        }
        let allowed = photoExtensions.union(videoExtensions)
        let targets = allFiles.filter { allowed.contains($0.pathExtension.lowercased()) }
        result.filesProcessed = targets.count
        if targets.isEmpty {
            writeLog(result, runFolder: runFolder)
            return result
        }

        // Pass paths via a tempfile arg-list. One exiftool invocation
        // handles all files — far faster than per-file spawning, and
        // sidesteps argv length limits on big runs.
        let argFile = runFolder.appendingPathComponent(".exiftool-args-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: argFile) }

        var argLines: [String] = ["-all=", "-overwrite_original", "-q"]
        argLines.append(contentsOf: targets.map { $0.path })
        do {
            try argLines.joined(separator: "\n").write(to: argFile, atomically: true, encoding: .utf8)
        } catch {
            result.errors.append("arg-file write failed: \(error.localizedDescription)")
            writeLog(result, runFolder: runFolder)
            return result
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exiftool)
        proc.arguments = ["-@", argFile.path]
        let errPipe = Pipe()
        proc.standardOutput = Pipe()
        proc.standardError = errPipe
        do { try proc.run() } catch {
            result.errors.append("exiftool launch failed: \(error.localizedDescription)")
            writeLog(result, runFolder: runFolder)
            return result
        }
        proc.waitUntilExit()
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if proc.terminationStatus == 0 {
            result.filesChanged = targets.count
        } else {
            result.errors.append("exiftool exit \(proc.terminationStatus): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        writeLog(result, runFolder: runFolder)
        return result
    }

    private static func writeLog(_ r: Result, runFolder: URL) {
        var s = "SlackSucker — metadata strip log\n"
        s += "Files processed: \(r.filesProcessed) (changed: \(r.filesChanged))\n"
        if !r.skipped.isEmpty {
            s += "\nSkipped:\n"
            for line in r.skipped { s += "  - \(line)\n" }
        }
        if !r.errors.isEmpty {
            s += "\nErrors:\n"
            for line in r.errors { s += "  - \(line)\n" }
        }
        try? s.write(to: runFolder.appendingPathComponent("metadata-log.txt"),
                     atomically: true, encoding: .utf8)
    }
}
