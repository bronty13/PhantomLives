import Foundation
import Combine

/// Spawns the bundled `slackdump archive` CLI as a child process and
/// republishes its stdout/stderr into SwiftUI-observable state. Modeled
/// on messages-exporter-gui's `ExportRunner` — the runner only formats
/// the invocation, streams output through a line buffer, and surfaces a
/// best-effort progress summary. Slackdump is the source of truth for
/// what actually happens on disk.
@MainActor
final class ArchiveRunner: ObservableObject {

    @Published private(set) var isRunning  = false
    @Published private(set) var isCancelling = false
    @Published private(set) var logLines: [String] = []
    @Published private(set) var runFolder: URL?
    @Published private(set) var lastError: String?
    @Published private(set) var lastExitStatus: Int32?
    @Published private(set) var runStats: RunStats = .empty
    /// True when the most recent run was cancelled and the output folder
    /// contains a slackdump.sqlite (i.e. resume is meaningful).
    @Published private(set) var resumeAvailable: Bool = false

    let history: RunHistoryStore

    private var runningProcess: Process?
    private var inflightRequest: ArchiveRequest?

    init(history: RunHistoryStore? = nil) {
        self.history = history ?? RunHistoryStore()
    }

    /// Kick off an archive run. No-ops if already running.
    func run(_ request: ArchiveRequest) async {
        guard !isRunning else { return }
        guard let bin = SlackdumpBinary.resolvedPath() else {
            lastError = "slackdump binary not found in app bundle. Rebuild the app via build-app.sh."
            return
        }

        logLines = []
        runFolder = nil
        lastError = nil
        lastExitStatus = nil
        runStats = RunStats()
        resumeAvailable = false
        switch request.timeRange {
        case .all:
            runStats.spanStart = nil
            runStats.spanEnd = nil
        case .range(let from, let to):
            runStats.spanStart = from
            runStats.spanEnd = to
        }
        inflightRequest = request

        do {
            try FileManager.default.createDirectory(at: request.outputDir, withIntermediateDirectories: true)
        } catch {
            lastError = "Couldn't create output directory: \(error.localizedDescription)"
            return
        }

        // Thread URLs get rewritten to a channel-scoped archive with a
        // tight time bracket — slackdump 4.x doesn't fetch files for
        // permalink-scoped archives. Surface that decision in the live
        // log so the user can correlate the actual argv with the form
        // they submitted.
        if case .threadURL(let url) = request.scope,
           ArchiveScope.parseThreadURL(url) != nil {
            appendLine("[scope] Thread URL — substituting channel archive with ±1s time bracket so slackdump fetches attachments.")
        }
        appendLine("$ \(bin) \(request.argumentList().joined(separator: " "))")

        let ok = await runProcessStreaming(
            executable: bin,
            arguments: request.argumentList(),
            cwd: nil
        )

        if isCancelling {
            isCancelling = false
            appendLine("[archive] Cancelled.")
            // If slackdump got far enough to create the SQLite checkpoint,
            // the user can resume. Surface that affordance to the UI.
            let dbPath = request.outputDir.appendingPathComponent("slackdump.sqlite")
            resumeAvailable = FileManager.default.fileExists(atPath: dbPath.path)
            runFolder = request.outputDir
            recordHistoryEntry(success: false)
            return
        }

        // Output folder is whatever request.outputDir resolved to —
        // slackdump writes the SQLite file inside that path.
        runFolder = request.outputDir
        // Always dump the captured log to <RunFolder>/archive.log so
        // "all logs and stuff in the run folder" is literally true.
        // The slackdump.sqlite stays where slackdump wrote it; we
        // never touch SQLite or `__avatars/`.
        writeArchiveLog(folder: request.outputDir)
        if ok {
            // Post-process: sort __uploads into media-category folders
            // when the user has the toggle on. Runs *before* we compute
            // outputBytes so the byte total reflects the final layout.
            if request.organizeFiles {
                let result = FileOrganizer.organize(runFolder: request.outputDir)
                if result.totalMoved > 0 {
                    appendLine("[organize] moved \(result.totalMoved) file"
                               + (result.totalMoved == 1 ? "" : "s")
                               + " into category folders"
                               + (result.collisions > 0
                                  ? " (\(result.collisions) renamed for name collisions)"
                                  : ""))
                }
                if !result.errors.isEmpty {
                    appendLine("[organize] \(result.errors.count) error(s) — see organize-log.txt")
                }
            }
            // Generate a plain-text chat transcript for targeted scopes
            // (channel / DM / thread). Entire-workspace runs are skipped
            // — too many conversations to flatten into one file, and the
            // user can fall back to `slackdump view` / convert -f html
            // for that case.
            if case .entireWorkspace = request.scope {
                // skip
            } else {
                do {
                    let out = try ChatExporter.export(
                        runFolder: request.outputDir,
                        filenameSlug: request.scope.slug,
                        scopeLabel: request.scope.humanLabel,
                        workspace: request.workspace
                    )
                    appendLine("[chat] wrote \(out.lastPathComponent) (\(out.path.replacingOccurrences(of: request.outputDir.path + "/", with: "")))")
                } catch {
                    appendLine("[chat] export failed — \(error.localizedDescription)")
                }
            }
            runStats.outputBytes = RunStats.computeOutputBytes(folder: request.outputDir)
        }
        recordHistoryEntry(success: ok)

        if !ok {
            lastError = "slackdump exited with status \(lastExitStatus ?? -1)."
        }
    }

    /// Persist the streamed slackdump log into `<RunFolder>/archive.log`.
    /// Failures are NSLogged and never propagated — a missing log file
    /// must not poison a successful archive.
    private func writeArchiveLog(folder: URL) {
        let url = folder.appendingPathComponent("archive.log")
        let body = logLines.joined(separator: "\n").appending("\n")
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("SlackSucker: archive.log write failed — \(error.localizedDescription)")
        }
    }

    /// Resume a previously cancelled / failed run by re-pointing at its
    /// output folder. Slackdump's `resume` subcommand picks up at the
    /// last checkpoint in the SQLite file.
    func resume(folder: URL) async {
        guard !isRunning else { return }
        guard let bin = SlackdumpBinary.resolvedPath() else {
            lastError = "slackdump binary not found in app bundle."
            return
        }
        logLines = []
        lastError = nil
        lastExitStatus = nil
        resumeAvailable = false
        runFolder = folder

        appendLine("$ \(bin) resume -o \(folder.path)")
        let ok = await runProcessStreaming(
            executable: bin,
            arguments: ["resume", "-o", folder.path],
            cwd: nil
        )
        if ok {
            runStats.outputBytes = RunStats.computeOutputBytes(folder: folder)
        } else if !isCancelling {
            lastError = "slackdump resume exited with status \(lastExitStatus ?? -1)."
        }
        isCancelling = false
    }

    func cancel() {
        guard isRunning, let process = runningProcess else { return }
        isCancelling = true
        process.terminate()
    }

    private func recordHistoryEntry(success: Bool) {
        guard let req = inflightRequest else { return }
        let entry = RunHistoryEntry(
            request: req,
            completedAt: Date(),
            runFolderPath: runFolder?.path,
            channelCount: runStats.channelCount,
            messageCount: runStats.messageCount,
            fileCount: runStats.fileCount,
            outputBytes: runStats.outputBytes,
            exitOK: success && runFolder != nil
        )
        history.record(entry)
        inflightRequest = nil
    }

    // MARK: - Process plumbing

    private func runProcessStreaming(
        executable: String,
        arguments: [String],
        cwd: URL?
    ) async -> Bool {
        isRunning = true
        defer { isRunning = false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = cwd }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = pipe

        var env = ProcessInfo.processInfo.environment
        // Same PATH-augmentation trick the sibling app uses: Finder-
        // launched .apps inherit a minimal PATH that omits /opt/homebrew
        // and /usr/local. Slackdump itself doesn't need those, but the
        // EZ-Login flow it might shell out to does, and we'd rather not
        // ship a busted child env on day one.
        env["PATH"] = Self.augmentedPATH(existing: env["PATH"])
        process.environment = env

        let buffer = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            buffer.append(chunk)
            for (line, replaces) in buffer.extractLines() {
                Task { @MainActor [weak self] in
                    self?.processLine(line, replacesLast: replaces)
                }
            }
        }

        do {
            try process.run()
        } catch {
            appendLine("[runner] failed to launch: \(error.localizedDescription)")
            pipe.fileHandleForReading.readabilityHandler = nil
            return false
        }
        runningProcess = process

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }
        runningProcess = nil
        pipe.fileHandleForReading.readabilityHandler = nil

        let tail = pipe.fileHandleForReading.availableData
        if !tail.isEmpty { buffer.append(tail) }
        for (line, replaces) in buffer.extractLines() { processLine(line, replacesLast: replaces) }
        for line in buffer.drainTrailing() { processLine(line) }

        lastExitStatus = process.terminationStatus
        return process.terminationStatus == 0
    }

    func processLine(_ line: String, replacesLast: Bool = false) {
        if replacesLast && !logLines.isEmpty {
            logLines[logLines.count - 1] = line
        } else {
            appendLine(line)
        }
        runStats.absorb(line)
    }

    private func appendLine(_ line: String) {
        logLines.append(line)
        // Cap at 4000 so a chatty `-v` run can't unbounded-grow the array.
        if logLines.count > 4000 {
            logLines.removeFirst(logLines.count - 4000)
        }
    }

    /// Mirror of messages-exporter-gui's PATH-augmentation logic. Adds
    /// the homebrew prefixes that Finder-launched .apps don't inherit.
    nonisolated static func augmentedPATH(existing: String?) -> String {
        let mustHave = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin"
        ]
        let baseline = existing?
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init) ?? []
        var seen = Set<String>()
        var ordered: [String] = []
        for p in mustHave + baseline {
            if seen.insert(p).inserted { ordered.append(p) }
        }
        return ordered.joined(separator: ":")
    }
}
