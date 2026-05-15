import Foundation

/// Runs the sibling `transcribe/` subproject against every audio /
/// video file under the run folder's `Audio/` and `Videos/` dirs,
/// emitting a `<name>.txt` transcript next to each source file.
///
/// Resolution order for the transcribe entrypoint:
///   1. `$SLACKSUCKER_TRANSCRIBE_BIN` env var (escape hatch)
///   2. `which transcribe` (if user added a shim to PATH)
///   3. `~/Documents/GitHub/PhantomLives/transcribe/transcribe.py`
///      (the sibling-checkout the maintainer ships)
///   4. None → skip with a single "transcribe not installed" notice
///
/// We never bundle `transcribe.py` inside the .app: it self-
/// bootstraps a multi-GB `.venv` on first run and that bootstrap
/// can't run from inside a signed bundle. PathScript pattern keeps
/// the model files and pip deps in the user's home where they
/// already live.
enum TranscriptionService {

    struct Result {
        var attempted: Int = 0
        var succeeded: Int = 0
        var failed: [String] = []
        var skipped: [String] = []
        /// Source-file → transcript-file pairs that were produced
        /// (useful for surfacing "open transcript" affordances later).
        var producedTranscripts: [(source: URL, transcript: URL)] = []
    }

    static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aiff", "aif", "flac", "ogg", "opus", "aac", "amr"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi", "wmv"]

    /// Locate the transcribe entrypoint via the resolution order
    /// documented above. Returns nil if none of the candidates exist.
    nonisolated static func resolveBinary() -> (executable: String, leadingArgs: [String])? {
        let env = ProcessInfo.processInfo.environment
        let fm = FileManager.default

        if let envPath = env["SLACKSUCKER_TRANSCRIBE_BIN"], !envPath.isEmpty,
           fm.isExecutableFile(atPath: envPath) {
            return (envPath, [])
        }
        let pathDirs = (env["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin").split(separator: ":")
        for dir in pathDirs {
            let candidate = "\(dir)/transcribe"
            if fm.isExecutableFile(atPath: candidate) {
                return (candidate, [])
            }
        }
        // Sibling-checkout fallback. Driven through python3 to honour
        // transcribe.py's own .venv bootstrap.
        let home = fm.homeDirectoryForCurrentUser
        let sibling = home.appendingPathComponent("Documents/GitHub/PhantomLives/transcribe/transcribe.py").path
        if fm.fileExists(atPath: sibling) {
            // python3 from PATH; transcribe.py re-execs itself inside
            // its own .venv on first run.
            for py in ["/opt/homebrew/bin/python3", "/usr/bin/python3", "/usr/local/bin/python3"] {
                if fm.isExecutableFile(atPath: py) {
                    return (py, [sibling])
                }
            }
        }
        return nil
    }

    /// Process every transcribable file under Videos/ and Audio/.
    /// `onLine` is invoked with each line streamed from transcribe.py,
    /// plus a `replacesLast` flag set when the line ended with bare
    /// `\r` (tqdm-style in-place progress updates). The runner uses
    /// that to overwrite the previous log line so the live view shows
    /// one continuously-updating progress bar per file instead of a
    /// scrolling wall of percentages.
    static func run(
        runFolder: URL,
        model: TranscriptionModel,
        onLine: @escaping (String, Bool) -> Void
    ) async -> Result {
        var result = Result()
        guard let (exe, leading) = resolveBinary() else {
            result.skipped.append("transcribe not found — install via $SLACKSUCKER_TRANSCRIBE_BIN, add `transcribe` to PATH, or check out PhantomLives/transcribe alongside SlackSucker")
            writeLog(result, runFolder: runFolder)
            onLine("[transcribe] skipped — no transcribe binary found", false)
            return result
        }

        let candidates = collectCandidates(runFolder: runFolder)
        if candidates.isEmpty {
            writeLog(result, runFolder: runFolder)
            return result
        }
        let total = candidates.count

        for (idx, source) in candidates.enumerated() {
            result.attempted += 1
            let progressTag = "[transcribe \(idx + 1)/\(total)]"
            let txtURL = source.deletingPathExtension().appendingPathExtension("txt")
            if FileManager.default.fileExists(atPath: txtURL.path) {
                result.skipped.append("\(source.lastPathComponent): transcript already exists")
                onLine("\(progressTag) skip \(source.lastPathComponent) — transcript already present", false)
                continue
            }

            let sizeStr = humanFileSize(at: source)
            onLine("\(progressTag) \(source.lastPathComponent) → \(txtURL.lastPathComponent) (\(sizeStr), model=\(model.rawValue))", false)
            let started = Date()

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            // Default verbosity (no -q, no -v) gets us transcribe.py's
            // phase lines ("Loading model", "Transcribing with model")
            // plus mlx-whisper's own stderr; both go through the
            // LineBuffer so tqdm bars overwrite cleanly.
            proc.arguments = leading + [
                "-i", source.path,
                "-o", txtURL.path,
                "-f", "txt",
                "-m", model.rawValue,
            ]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = ArchiveRunner.augmentedPATH(existing: env["PATH"])
            // mlx-whisper checks PYTHONUNBUFFERED for tqdm flushing.
            env["PYTHONUNBUFFERED"] = "1"
            proc.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe

            // Merge stdout + stderr into one LineBuffer. transcribe.py
            // writes its `log()` output to stderr; some mlx-whisper
            // internals write to stdout. Order matters less than
            // surfacing them at all.
            let buffer = LineBuffer()
            let pump: @Sendable (FileHandle) -> Void = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                buffer.append(chunk)
                for (line, replaces) in buffer.extractLines() {
                    onLine("\(progressTag) \(line)", replaces)
                }
            }
            outPipe.fileHandleForReading.readabilityHandler = pump
            errPipe.fileHandleForReading.readabilityHandler = pump

            do { try proc.run() } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                result.failed.append("\(source.lastPathComponent): launch failed — \(error.localizedDescription)")
                onLine("\(progressTag) \(source.lastPathComponent) — launch failed: \(error.localizedDescription)", false)
                continue
            }

            // Bridge sync Process exit into async/await so the UI
            // stays responsive between files.
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                proc.terminationHandler = { _ in cont.resume() }
            }
            // Drain any trailing data + retire the readability handlers
            // before the file handles get closed — readabilityHandler
            // outlives waitUntilExit on macOS 14+.
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            for handle in [outPipe.fileHandleForReading, errPipe.fileHandleForReading] {
                let tail = handle.availableData
                if !tail.isEmpty { buffer.append(tail) }
            }
            for (line, replaces) in buffer.extractLines() {
                onLine("\(progressTag) \(line)", replaces)
            }
            for line in buffer.drainTrailing() {
                onLine("\(progressTag) \(line)", false)
            }

            let elapsed = Date().timeIntervalSince(started)
            if proc.terminationStatus == 0 && FileManager.default.fileExists(atPath: txtURL.path) {
                result.succeeded += 1
                result.producedTranscripts.append((source, txtURL))
                onLine("\(progressTag) ✓ \(source.lastPathComponent) in \(formatDuration(elapsed))", false)
            } else {
                let reason = "exit \(proc.terminationStatus)"
                result.failed.append("\(source.lastPathComponent): \(reason)")
                onLine("\(progressTag) ✗ \(source.lastPathComponent) — \(reason) after \(formatDuration(elapsed))", false)
            }
        }
        writeLog(result, runFolder: runFolder)
        return result
    }

    private static func humanFileSize(at url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let fmt = ByteCountFormatter()
        fmt.allowedUnits = [.useMB, .useGB]
        fmt.countStyle = .file
        return fmt.string(fromByteCount: Int64(bytes))
    }

    nonisolated static func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m\(s % 60)s"
    }

    private static func collectCandidates(runFolder: URL) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for sub in ["Videos", "Audio"] {
            let dir = runFolder.appendingPathComponent(sub, isDirectory: true)
            guard fm.fileExists(atPath: dir.path) else { continue }
            for url in HashService.filesUnder(dir) {
                let ext = url.pathExtension.lowercased()
                if videoExtensions.contains(ext) || audioExtensions.contains(ext) {
                    out.append(url)
                }
            }
        }
        return out.sorted { $0.path < $1.path }
    }

    private static func writeLog(_ r: Result, runFolder: URL) {
        var s = "SlackSucker — transcription log\n"
        s += "Attempted: \(r.attempted), succeeded: \(r.succeeded), failed: \(r.failed.count), skipped: \(r.skipped.count)\n"
        if !r.skipped.isEmpty {
            s += "\nSkipped:\n"
            for line in r.skipped { s += "  - \(line)\n" }
        }
        if !r.failed.isEmpty {
            s += "\nFailed:\n"
            for line in r.failed { s += "  - \(line)\n" }
        }
        try? s.write(to: runFolder.appendingPathComponent("transcribe-log.txt"),
                     atomically: true, encoding: .utf8)
    }
}
