import Foundation
import Combine

/// One row parsed from `slackdump workspace list`.
struct SlackWorkspace: Identifiable, Equatable, Codable {
    var id: String { name }
    var name: String
    /// `*` next to the name in slackdump's `list` output → this is the
    /// "current" workspace slackdump will pick when no `-workspace` flag
    /// is passed.
    var isCurrent: Bool
}

/// Wraps the `slackdump workspace …` subcommand surface. We never reach
/// into slackdump's encrypted credential cache directly — every state
/// transition (list, add, select, delete) goes through the binary, so
/// the GUI never has to handle a raw token.
@MainActor
final class WorkspaceService: ObservableObject {

    @Published private(set) var workspaces: [SlackWorkspace] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isBusy: Bool = false
    /// Live stdout/stderr from the in-flight `workspace new` flow so the
    /// sheet can show the EZ-Login progress without freezing on a spinner.
    @Published private(set) var newWorkspaceLog: [String] = []
    /// True when slackdump has emitted an interactive prompt that needs
    /// a user answer (currently only the "Overwrite? (y/N)" path when a
    /// workspace name collides). The UI surfaces a confirm dialog and
    /// calls `answerOverwrite(yes:)` to write the response into stdin.
    @Published private(set) var pendingOverwritePrompt: String?

    private let binary: () -> String?
    private var runningNewProcess: Process?
    private var newStdinPipe: Pipe?

    init(binary: @escaping () -> String? = SlackdumpBinary.resolvedPath) {
        self.binary = binary
    }

    /// Parse the output of `slackdump workspace list`. Slackdump's actual
    /// format (v4.x) looks like:
    ///
    ///     Workspaces in "/Users/.../Library/Caches/slackdump":
    ///
    ///     => default (file: provider.bin, last modified: 2026-05-15 12:02:46)
    ///        other   (file: ...)
    ///
    ///     Current workspace is marked with ' => '.
    ///
    /// `=> ` (with a trailing space) marks the current workspace; the
    /// workspace name is what sits between the marker and the `(` that
    /// starts the metadata column. Any line without that shape is
    /// header / footer chrome.
    nonisolated static func parseList(_ stdout: String) -> [SlackWorkspace] {
        var out: [SlackWorkspace] = []
        for raw in stdout.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Skip the header ("Workspaces in ..."), the footer
            // ("Current workspace is marked with..."), and any other
            // line that doesn't carry a workspace metadata column.
            if trimmed.lowercased().hasPrefix("workspaces in") { continue }
            if trimmed.lowercased().hasPrefix("current workspace") { continue }
            // Real rows always carry a "(file: ..." metadata block.
            guard let openParen = trimmed.range(of: " (file:") else { continue }
            let beforeParen = trimmed[..<openParen.lowerBound]
            let isCurrent = beforeParen.hasPrefix("=>")
            // Strip the current marker, then trim — what remains is the
            // workspace name (single token, but we tolerate spaces in
            // case slackdump ever quotes names that contain them).
            let nameSlice = beforeParen
                .drop(while: { $0 == "=" || $0 == ">" || $0 == " " })
            let name = String(nameSlice).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            out.append(SlackWorkspace(name: name, isCurrent: isCurrent))
        }
        return out
    }

    /// Refresh `workspaces` by shelling out to `slackdump workspace list`.
    /// Errors are surfaced via `lastError` rather than thrown so the
    /// caller can keep its `Task` flow tidy.
    func refresh() async {
        guard !isBusy else { return }
        guard let bin = binary() else {
            lastError = "slackdump binary not found in app bundle."
            return
        }
        isBusy = true
        defer { isBusy = false }

        let result = await Self.runCapturing(binary: bin, arguments: ["workspace", "list"])
        switch result {
        case .success(let stdout):
            workspaces = Self.parseList(stdout)
            lastError = nil
        case .failure(let err):
            lastError = err
        }
    }

    /// Pick which workspace slackdump treats as "current". Equivalent
    /// to the user running `slackdump workspace select foo` themselves.
    func select(_ name: String) async {
        guard let bin = binary() else { return }
        let result = await Self.runCapturing(binary: bin, arguments: ["workspace", "select", name])
        if case .failure(let err) = result {
            lastError = err
        }
        await refresh()
    }

    func delete(_ name: String) async {
        guard let bin = binary() else { return }
        let result = await Self.runCapturing(binary: bin, arguments: ["workspace", "del", name])
        if case .failure(let err) = result {
            lastError = err
        }
        await refresh()
    }

    /// Spawn `slackdump workspace new <name>`. Slackdump runs its own
    /// EZ-Login flow on launch; we stream stdout/stderr into
    /// `newWorkspaceLog` so the user can see what's happening, and pipe
    /// stdin so prompts (e.g. "Overwrite? (y/N)" when the name collides)
    /// can actually be answered. Without stdin slackdump busy-loops on
    /// the prompt because it sees EOF.
    ///
    /// `name` is forwarded as the positional argument. `nil` lets
    /// slackdump default to "default" (and prompt if it already exists).
    func addNewWorkspace(name: String?) async {
        guard !isBusy else { return }
        guard let bin = binary() else {
            lastError = "slackdump binary not found in app bundle."
            return
        }
        isBusy = true
        newWorkspaceLog = []
        pendingOverwritePrompt = nil
        defer { isBusy = false; pendingOverwritePrompt = nil }

        var args = ["workspace", "new"]
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(name)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = pipe
        // Real (open) stdin so slackdump's interactive prompts can be
        // answered by `answerOverwrite(yes:)`. Without this slackdump
        // reads EOF from stdin and reprompts forever.
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        newStdinPipe = stdinPipe

        let buffer = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            buffer.append(chunk)
            for (line, _) in buffer.extractLines() {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.newWorkspaceLog.append(line)
                    if self.newWorkspaceLog.count > 1000 {
                        self.newWorkspaceLog.removeFirst(200)
                    }
                    // Detect the "already exists. Overwrite?" prompt and
                    // hoist it into a confirm dialog. Only fire once per
                    // prompt sequence — slackdump reprompts after a bad
                    // answer, but only the first detection should pop
                    // the UI.
                    if self.pendingOverwritePrompt == nil,
                       let collision = Self.detectOverwritePrompt(in: line) {
                        self.pendingOverwritePrompt = collision
                    }
                }
            }
        }

        do {
            try process.run()
        } catch {
            lastError = "Couldn't launch slackdump: \(error.localizedDescription)"
            pipe.fileHandleForReading.readabilityHandler = nil
            return
        }
        runningNewProcess = process

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }
        runningNewProcess = nil
        newStdinPipe = nil
        pipe.fileHandleForReading.readabilityHandler = nil
        let tail = pipe.fileHandleForReading.availableData
        if !tail.isEmpty {
            buffer.append(tail)
            for (line, _) in buffer.extractLines() {
                newWorkspaceLog.append(line)
            }
        }
        if process.terminationStatus != 0 {
            lastError = "slackdump workspace new exited \(process.terminationStatus)."
        }
        await refresh()
    }

    /// Write a y/N answer to the running `workspace new` process's stdin
    /// and clear the pending-prompt flag. No-op if nothing is running.
    func answerOverwrite(yes: Bool) {
        guard let stdin = newStdinPipe else { return }
        let response = (yes ? "y\n" : "N\n").data(using: .utf8)!
        do {
            try stdin.fileHandleForWriting.write(contentsOf: response)
        } catch {
            NSLog("SlackSucker: failed to write overwrite answer — \(error.localizedDescription)")
        }
        pendingOverwritePrompt = nil
        // If the user answered "No", slackdump will exit on its own after
        // reading the response — no need to terminate from here.
    }

    /// Cancel an in-flight `workspace new` (terminates the browser-auth
    /// child process). No-op if nothing is running.
    func cancelNewWorkspace() {
        // Closing stdin first prevents slackdump from emitting another
        // round of prompts during termination.
        try? newStdinPipe?.fileHandleForWriting.close()
        runningNewProcess?.terminate()
    }

    /// Spot slackdump's "Workspace <X> already exists. Overwrite? (y/N)"
    /// line and return the colliding workspace name. The exact wording
    /// has shifted across slackdump versions; we look for the recognisable
    /// "already exists. Overwrite" substring and pull the quoted name
    /// out of the prefix.
    nonisolated static func detectOverwritePrompt(in line: String) -> String? {
        guard line.lowercased().contains("already exists. overwrite") else { return nil }
        if let r = line.range(of: #""([^"]+)""#, options: .regularExpression) {
            return String(line[r].dropFirst().dropLast())
        }
        return "this workspace"
    }

    // MARK: - Process helpers

    private enum CaptureResult {
        case success(String)
        case failure(String)
    }

    private static func runCapturing(binary: String, arguments: [String]) async -> CaptureResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError  = err
        do {
            try process.run()
        } catch {
            return .failure("Couldn't launch slackdump: \(error.localizedDescription)")
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }
        let stdoutData = out.fileHandleForReading.readDataToEndOfFile()
        let stderrData = err.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            let trimmedErr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(trimmedErr.isEmpty
                ? "slackdump exited \(process.terminationStatus)"
                : trimmedErr)
        }
        return .success(stdout)
    }
}
