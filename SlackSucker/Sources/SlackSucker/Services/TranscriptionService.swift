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
    /// `onLine` is invoked with each interesting status line so the
    /// runner can surface it in the live log.
    static func run(
        runFolder: URL,
        model: TranscriptionModel,
        onLine: @escaping (String) -> Void
    ) async -> Result {
        var result = Result()
        guard let (exe, leading) = resolveBinary() else {
            result.skipped.append("transcribe not found — install via $SLACKSUCKER_TRANSCRIBE_BIN, add `transcribe` to PATH, or check out PhantomLives/transcribe alongside SlackSucker")
            writeLog(result, runFolder: runFolder)
            onLine("[transcribe] skipped — no transcribe binary found")
            return result
        }

        let candidates = collectCandidates(runFolder: runFolder)
        if candidates.isEmpty {
            writeLog(result, runFolder: runFolder)
            return result
        }

        for source in candidates {
            result.attempted += 1
            let txtURL = source.deletingPathExtension().appendingPathExtension("txt")
            if FileManager.default.fileExists(atPath: txtURL.path) {
                result.skipped.append("\(source.lastPathComponent): transcript already exists")
                onLine("[transcribe] skip \(source.lastPathComponent) — transcript already present")
                continue
            }
            onLine("[transcribe] \(source.lastPathComponent) → \(txtURL.lastPathComponent) (model=\(model.rawValue))")

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            proc.arguments = leading + [
                "-i", source.path,
                "-o", txtURL.path,
                "-f", "txt",
                "-m", model.rawValue,
                "-q"
            ]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = ArchiveRunner.augmentedPATH(existing: env["PATH"])
            proc.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe

            do { try proc.run() } catch {
                result.failed.append("\(source.lastPathComponent): launch failed — \(error.localizedDescription)")
                onLine("[transcribe] \(source.lastPathComponent) — launch failed: \(error.localizedDescription)")
                continue
            }

            // Bridge sync Process exit into async/await so the UI
            // stays responsive between files. termination handler must
            // be Sendable-safe — a plain continuation works.
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                proc.terminationHandler = { _ in cont.resume() }
            }

            let stderrText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                                    encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if proc.terminationStatus == 0 && FileManager.default.fileExists(atPath: txtURL.path) {
                result.succeeded += 1
                result.producedTranscripts.append((source, txtURL))
                onLine("[transcribe] ✓ \(source.lastPathComponent)")
            } else {
                let reason = stderrText.isEmpty
                    ? "exit \(proc.terminationStatus)"
                    : "exit \(proc.terminationStatus) — \(stderrText.prefix(200))"
                result.failed.append("\(source.lastPathComponent): \(reason)")
                onLine("[transcribe] ✗ \(source.lastPathComponent) — \(reason)")
            }
        }
        writeLog(result, runFolder: runFolder)
        return result
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
