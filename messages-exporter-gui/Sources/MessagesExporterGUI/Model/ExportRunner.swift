import Foundation
import Combine

/// Thread-safe accumulator for byte chunks that may not align with
/// newline boundaries. Locked because Pipe's readabilityHandler closure
/// is Sendable but cannot directly capture mutable Data.
private final class LineBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }

    /// Pulls every complete (newline-terminated) line out of the buffer,
    /// leaving any partial trailing fragment behind.
    func extractLines() -> [String] {
        lock.lock(); defer { lock.unlock() }
        var lines: [String] = []
        while let nlIndex = data.firstIndex(of: 0x0A) {
            let lineData = data.prefix(upTo: nlIndex)
            data.removeSubrange(data.startIndex...nlIndex)
            lines.append(String(data: lineData, encoding: .utf8) ?? "")
        }
        return lines
    }

    /// Empties whatever remains (a final line without a trailing newline).
    func drainTrailing() -> [String] {
        lock.lock(); defer { lock.unlock() }
        guard !data.isEmpty else { return [] }
        let tail = String(data: data, encoding: .utf8) ?? ""
        data.removeAll()
        return tail.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}

/// Spawns the `export_messages` CLI as a child process and republishes its
/// stdout/stderr into SwiftUI-observable state. The CLI is the source of
/// truth — this runner only formats the invocation, parses the well-known
/// `[N/5]` progress markers, and captures the run folder path printed at
/// stage 4 so the UI can offer "Reveal in Finder" on completion.
@MainActor
final class ExportRunner: ObservableObject {

    @Published private(set) var isRunning  = false
    @Published private(set) var stage      = 0          // 0...5
    @Published private(set) var logLines: [String] = []
    @Published private(set) var runFolder: URL?
    @Published private(set) var lastError: String?
    @Published private(set) var lastExitStatus: Int32?

    /// Resolved path to the installed CLI. Computed once — if the user
    /// installs after launching the app, hit "Run" again and it'll be
    /// rechecked via cliIsInstalled().
    static let cliPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.local/bin/export_messages"
    }()

    /// install.sh path, derived from the GUI app's location relative to
    /// the messages-exporter sibling subproject. We cannot assume the .app
    /// is anywhere in particular at runtime, so we look for the script in
    /// the same parent directory the .app was built into (PhantomLives/),
    /// then fall back to a few common dev locations.
    static func installScriptCandidates() -> [String] {
        let bundleParent = Bundle.main.bundleURL.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(bundleParent)/../messages-exporter/install.sh",
            "\(home)/Documents/GitHub/PhantomLives/messages-exporter/install.sh"
        ]
    }

    static func cliIsInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: cliPath)
    }

    /// Run the CLI install.sh from the messages-exporter sibling
    /// subproject. Streams its output into the same logLines pane so the
    /// user sees the brew/pip steps. Resolves to true when install
    /// succeeded and the cli now exists on disk.
    func installCLI() async -> Bool {
        guard !isRunning else { return false }
        guard let script = Self.installScriptCandidates()
            .first(where: { FileManager.default.isReadableFile(atPath: $0) }) else {
            appendLine("[install] Could not locate messages-exporter/install.sh next to the app.")
            return false
        }
        appendLine("[install] Running \(script)")
        let ok = await runProcessStreaming(
            executable: "/bin/bash",
            arguments: [script],
            cwd: URL(fileURLWithPath: script).deletingLastPathComponent()
        )
        let installed = Self.cliIsInstalled()
        appendLine(installed
            ? "[install] CLI is now installed at \(Self.cliPath)"
            : "[install] install.sh exited but \(Self.cliPath) was not created.")
        _ = ok
        return installed
    }

    /// Kick off an export run for the given request. No-ops if already
    /// running. UI should disable the Run button while isRunning is true.
    func run(_ request: ExportRequest) async {
        guard !isRunning else { return }
        guard Self.cliIsInstalled() else {
            lastError = "export_messages CLI is not installed at \(Self.cliPath)."
            return
        }

        // Reset per-run state.
        logLines = []
        stage = 0
        runFolder = nil
        lastError = nil
        lastExitStatus = nil

        appendLine("$ \(Self.cliPath) \(request.argumentList().joined(separator: " "))")

        let ok = await runProcessStreaming(
            executable: Self.cliPath,
            arguments: request.argumentList(),
            cwd: nil
        )

        // CLI exits 0 even when nothing matched. The run folder is the
        // best signal of "did anything actually happen?"
        if ok && runFolder == nil {
            lastError = "Export finished with no output folder — likely no contact match or no messages in range."
        } else if !ok {
            // Detect the specific Full Disk Access failure so we can give
            // the user actionable guidance instead of just an exit code.
            // The CLI bubbles the SQLite error verbatim; child processes
            // inherit TCC entitlements from this app, so it's THIS app
            // that needs FDA — the Terminal you tested with before is
            // irrelevant.
            let log = logLines.joined(separator: "\n")
            if log.contains("authorization denied") || log.contains("operation not permitted") {
                lastError = "Full Disk Access denied. Open System Settings → Privacy & Security → Full Disk Access, add MessagesExporterGUI.app, then quit and relaunch it."
            } else {
                lastError = "export_messages exited with status \(lastExitStatus ?? -1)."
            }
        }
    }

    // MARK: - Process plumbing

    /// Spawns a process with merged stdout+stderr, streams output through
    /// processLine() on the main actor, and returns true iff exit status
    /// was zero. Pattern adapted from PurpleIRC's BackupService but with
    /// async readability rather than waitUntilExit-then-read.
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
        // Disable Python output buffering so [N/5] markers reach us in
        // real time rather than at process exit.
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        process.environment = env

        // Buffer for partial-line accumulation. readabilityHandler runs
        // serially per FileHandle, but Swift's concurrency checker can't
        // see that — wrap state in a reference type with a lock so the
        // closure stays Sendable-safe.
        let buffer = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            buffer.append(chunk)
            for line in buffer.extractLines() {
                Task { @MainActor [weak self] in
                    self?.processLine(line)
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

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }
        pipe.fileHandleForReading.readabilityHandler = nil

        // Drain anything remaining (final line without a trailing newline).
        let tail = pipe.fileHandleForReading.availableData
        if !tail.isEmpty { buffer.append(tail) }
        for line in buffer.extractLines() { processLine(line) }
        for line in buffer.drainTrailing() { processLine(line) }

        lastExitStatus = process.terminationStatus
        return process.terminationStatus == 0
    }

    // MARK: - Line parsing (visible for tests)

    func processLine(_ line: String) {
        appendLine(line)
        if let s = Self.stageNumber(in: line) {
            stage = s
        }
        if let folder = Self.runFolderPath(in: line) {
            runFolder = URL(fileURLWithPath: folder)
        }
    }

    private func appendLine(_ line: String) {
        logLines.append(line)
        // Cap so a runaway export can't unbounded-grow the array.
        if logLines.count > 2000 {
            logLines.removeFirst(logLines.count - 2000)
        }
    }

    /// Matches the CLI's `[N/5]` markers (1...5). Returns nil otherwise.
    nonisolated static func stageNumber(in line: String) -> Int? {
        guard let openIdx = line.firstIndex(of: "[") else { return nil }
        let after = line.index(after: openIdx)
        guard line.indices.contains(after),
              let closeIdx = line[after...].firstIndex(of: "]") else { return nil }
        let inner = line[after..<closeIdx]
        let parts = inner.split(separator: "/")
        guard parts.count == 2, parts[1] == "5",
              let n = Int(parts[0]), (1...5).contains(n) else { return nil }
        return n
    }

    /// Captures the run folder printed by the CLI at stage 4:
    ///     "[4/5] Writing to messages_export/Sallie_20260426_172132"
    /// Returns nil for any other line.
    nonisolated static func runFolderPath(in line: String) -> String? {
        let marker = "[4/5] Writing to "
        guard let range = line.range(of: marker) else { return nil }
        let path = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
