import Foundation
import Combine
import AppKit

/// Thread-safe accumulator for byte chunks that may not align with
/// newline boundaries. Locked because Pipe's readabilityHandler closure
/// is Sendable but cannot directly capture mutable Data.
private final class LineBuffer: @unchecked Sendable {
    private var data = Data()
    private var lastWasCarriageReturn = false   // for CR-overwrite tracking
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }

    /// Pulls every complete line out of the buffer, splitting on \n, \r\n,
    /// or bare \r. Returns (text, replacesLast) pairs — replacesLast is true
    /// when the previous terminator was a bare \r, matching terminal carriage-
    /// return overwrite behavior (e.g. pip progress bars).
    func extractLines() -> [(String, replacesLast: Bool)] {
        lock.lock(); defer { lock.unlock() }
        var result: [(String, Bool)] = []
        while true {
            // Find the earliest \n or \r.
            guard let idx = data.indices.first(where: { data[$0] == 0x0A || data[$0] == 0x0D })
            else { break }

            let lineData = data.prefix(upTo: idx)
            let isCR = data[idx] == 0x0D
            var removeEnd = data.index(after: idx)
            // \r\n → treat as a single newline, not as a bare CR.
            let isBareCR = isCR && (removeEnd >= data.endIndex || data[removeEnd] != 0x0A)
            if isCR && !isBareCR { removeEnd = data.index(after: removeEnd) }
            data.removeSubrange(data.startIndex..<removeEnd)

            let text = String(data: lineData, encoding: .utf8) ?? ""
            let replaces = lastWasCarriageReturn
            lastWasCarriageReturn = isBareCR
            result.append((text, replaces))
        }
        return result
    }

    /// Empties whatever remains (a final line without a trailing newline).
    func drainTrailing() -> [String] {
        lock.lock(); defer { lock.unlock() }
        guard !data.isEmpty else { return [] }
        let tail = String(data: data, encoding: .utf8) ?? ""
        data.removeAll()
        lastWasCarriageReturn = false
        return tail.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}

/// Whether `~/Library/Messages/chat.db` is readable by this process.
/// Driven by `ExportRunner.checkFullDiskAccess()` — refreshed on launch
/// and on demand from the FDA sheet. `.unknown` is the pre-check value;
/// `.granted` and `.denied` are persisted decisions. We can never go from
/// `.denied` to `.granted` without a relaunch (TCC pins the cdhash at
/// process spawn), so the sheet's main call to action is "Quit and
/// relaunch" rather than "Re-check".
enum FullDiskAccessStatus: Equatable {
    case unknown
    case granted
    case denied
    case missingDB   // Messages.app never used — treat as a non-blocking case
}

/// Spawns the `export_messages` CLI as a child process and republishes its
/// stdout/stderr into SwiftUI-observable state. The CLI is the source of
/// truth — this runner only formats the invocation, parses the well-known
/// `[N/5]` progress markers, and captures the run folder path printed at
/// stage 4 so the UI can offer "Reveal in Finder" on completion.
@MainActor
final class ExportRunner: ObservableObject {

    @Published private(set) var isRunning  = false
    @Published private(set) var isCancelling = false
    @Published private(set) var stage      = 0          // 0...5
    @Published private(set) var logLines: [String] = []
    @Published private(set) var runFolder: URL?
    @Published private(set) var lastError: String?
    @Published private(set) var lastExitStatus: Int32?
    @Published private(set) var fdaStatus: FullDiskAccessStatus = .unknown

    private var runningProcess: Process?

    /// Resolved path to the installed CLI. Computed once — if the user
    /// installs after launching the app, hit "Run" again and it'll be
    /// rechecked via cliIsInstalled().
    static let cliPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.local/bin/export_messages"
    }()

    /// chat.db location — the canonical FDA-gated file we probe.
    static let messagesDBPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Messages/chat.db"
    }()

    /// Bundle ID used by `tccutil reset` to wipe stale TCC entries.
    /// Hard-coded to match Info.plist's CFBundleIdentifier — a runtime
    /// `Bundle.main.bundleIdentifier` lookup would return nil in unit-test
    /// contexts and `swift run` (no .app wrapper).
    static let bundleIdentifier = "com.bronty13.MessagesExporterGUI"

    /// Pure probe: try to open + read 1 byte from `path`, classify into
    /// `FullDiskAccessStatus`. Extracted so tests can drive it against a
    /// tempdir, without needing to monkey with the real chat.db.
    ///
    /// We open + read 1 byte rather than `isReadableFile` because the
    /// latter is a stat-based answer that doesn't always match TCC's
    /// runtime decision — TCC enforces at I/O time on macOS 14.
    nonisolated static func probeReadable(path: String) -> FullDiskAccessStatus {
        guard FileManager.default.fileExists(atPath: path) else {
            // chat.db absent — Messages.app has never been used on this
            // account. Don't block the user with an FDA sheet; the CLI
            // will print its own clearer error if they try to export.
            return .missingDB
        }
        let url = URL(fileURLWithPath: path)
        do {
            let handle = try FileHandle(forReadingFrom: url)
            _ = try handle.read(upToCount: 1)
            try handle.close()
            return .granted
        } catch {
            return .denied
        }
    }

    /// Probe whether this process can read `~/Library/Messages/chat.db`.
    /// macOS gates that file behind Full Disk Access; without FDA the
    /// open() syscall returns EPERM regardless of POSIX permissions.
    ///
    /// Side effect: updates `fdaStatus`. Idempotent and cheap; safe to
    /// call multiple times. Note that going from .denied -> .granted in
    /// a single launch is impossible (TCC pins the cdhash at process
    /// spawn); the user must quit and relaunch after granting.
    func checkFullDiskAccess() {
        fdaStatus = Self.probeReadable(path: Self.messagesDBPath)
    }

    /// Open System Settings → Privacy & Security → Full Disk Access. The
    /// `x-apple.systempreferences:` URL scheme is documented for security
    /// and Privacy panes; this anchor is stable across macOS 13–14.
    static func openPrivacySettings() {
        let urlString =
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Wipe any existing FDA TCC rows for this bundle ID via `tccutil`.
    ///
    /// Use case: ad-hoc signing rotates `cdhash` on every rebuild, and
    /// TCC keys grants on (bundle ID, cdhash). After several rebuilds
    /// the user accumulates duplicate "MessagesExporterGUI"/"…  2"
    /// entries — `tccutil reset` removes all of them so the next
    /// re-grant produces a single clean entry.
    ///
    /// Returns true on `tccutil` exit 0. The running process still
    /// holds its old TCC decision in memory, so the user must quit and
    /// relaunch after this for any newly-granted access to take effect.
    func resetTCCEntries() async -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "SystemPolicyAllFiles", Self.bundleIdentifier]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe
        do {
            try p.run()
        } catch {
            appendLine("[tccutil] failed to launch: \(error.localizedDescription)")
            return false
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            p.terminationHandler = { _ in cont.resume() }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let s = String(data: data, encoding: .utf8), !s.isEmpty {
            for line in s.split(separator: "\n") {
                appendLine("[tccutil] \(line)")
            }
        }
        return p.terminationStatus == 0
    }

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
        if isCancelling {
            isCancelling = false
            appendLine("[export] Cancelled.")
            return
        }
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
                // Reflect the runtime denial back into the preflight state
                // so the persistent banner appears even when the launch-
                // time probe initially passed (rare, but possible if TCC
                // policy changed between launch and the first export).
                fdaStatus = .denied
                lastError = "Full Disk Access denied. Open System Settings → Privacy & Security → Full Disk Access, add MessagesExporterGUI.app, then quit and relaunch it."
            } else {
                lastError = "export_messages exited with status \(lastExitStatus ?? -1)."
            }
        }
    }

    /// Terminate the running export. No-op if nothing is running.
    func cancel() {
        guard isRunning, let process = runningProcess else { return }
        isCancelling = true
        process.terminate()
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

        // Drain anything remaining (final line without a trailing newline).
        let tail = pipe.fileHandleForReading.availableData
        if !tail.isEmpty { buffer.append(tail) }
        for (line, replaces) in buffer.extractLines() { processLine(line, replacesLast: replaces) }
        for line in buffer.drainTrailing() { processLine(line) }

        lastExitStatus = process.terminationStatus
        return process.terminationStatus == 0
    }

    // MARK: - Line parsing (visible for tests)

    func processLine(_ line: String, replacesLast: Bool = false) {
        if replacesLast && !logLines.isEmpty {
            logLines[logLines.count - 1] = line
        } else {
            appendLine(line)
        }
        if let s = Self.stageNumber(in: line) { stage = s }
        if let folder = Self.runFolderPath(in: line) { runFolder = URL(fileURLWithPath: folder) }
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
