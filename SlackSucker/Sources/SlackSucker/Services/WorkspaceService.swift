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
    /// Name of the workspace just added by a successful `workspace new`
    /// run. Published so the sheet can pick it up and auto-select —
    /// otherwise the workspace lands in the list but the user has to
    /// hunt for a "Select" button to make it current.
    @Published private(set) var lastAddedWorkspaceName: String?

    private let binary: () -> String?
    private var runningNewProcess: Process?
    /// Master end of the pseudo-terminal that drives the in-flight
    /// `workspace new` child. We write user responses (y/N) here and read
    /// the child's stdout/stderr off the same fd. See `openPTYPair` for
    /// why a PTY is required.
    private var newPTYMaster: FileHandle?
    /// One-shot flag: have we already dismissed slackdump's `huh.Select`
    /// auth-method picker by sending a bare Enter? Reset per spawn.
    private var didDismissAuthMenu: Bool = false

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
    /// EZ-Login browser flow on launch; we stream stdout/stderr into
    /// `newWorkspaceLog` so the user can see what's happening, and write
    /// user responses (e.g. y/N to "Overwrite?" when the name collides)
    /// to the same fd.
    ///
    /// We hand slackdump the slave end of a pseudo-terminal rather than a
    /// `Pipe`. slackdump checks `isatty(stderr)` before launching Rod and
    /// errors out with "browser auth is not supported in dumb terminals"
    /// when the check fails — anonymous pipes always fail it. The PTY
    /// satisfies the check while still letting us multiplex everything
    /// through a single FileHandle on our side.
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
        didDismissAuthMenu = false
        defer { isBusy = false; pendingOverwritePrompt = nil }

        // `-v` is registered on the `workspace new` subcommand's flag
        // set (not the top level), so it has to come AFTER `new`. Helps
        // diagnose which auth path slackdump actually takes.
        var args = ["workspace", "new", "-v"]
        // slackdump v4.3 uses the positional arg as the workspace key
        // for BOTH the saved-credentials filename and the post-auth
        // "select as current" step. When the arg is a URL, the select
        // step fails with `no such workspace: "https://..."` and the
        // captured token+cookie get discarded. Reduce a URL to its
        // first hostname label so both steps see the same name.
        var spawnedWorkspaceName: String?
        if let raw = name?.trimmingCharacters(in: .whitespaces), !raw.isEmpty {
            let arg = Self.workspaceArg(from: raw)
            args.append(arg)
            spawnedWorkspaceName = arg
        }
        // Echo the exact argv we're about to exec so the log shows
        // whether the URL/name actually made it through.
        let quoted = args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ")
        newWorkspaceLog.append("[slacksucker] spawning: slackdump \(quoted)")

        guard let pty = Self.openPTYPair() else {
            lastError = "Couldn't allocate a pseudo-terminal for slackdump."
            return
        }
        let masterHandle = FileHandle(fileDescriptor: pty.masterFD, closeOnDealloc: true)
        // We close the slave fd manually after spawn — Foundation has
        // already dup'd it into the child by then. `closeOnDealloc:
        // false` keeps the FileHandle from racing us to it.
        let slaveHandle  = FileHandle(fileDescriptor: pty.slaveFD,  closeOnDealloc: false)
        newPTYMaster = masterHandle

        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = args
        process.standardInput  = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError  = slaveHandle
        // Some Go libraries slackdump links against gate their terminal
        // behaviour on $TERM; default to xterm-256color so we look like a
        // normal interactive shell.
        var env = ProcessInfo.processInfo.environment
        if env["TERM"] == nil { env["TERM"] = "xterm-256color" }
        process.environment = env

        let buffer = LineBuffer()
        masterHandle.readabilityHandler = { handle in
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
                    // Slackdump v4.3 pops a huh.Select auth-method picker
                    // after `tryLoad()` fails. The default-highlighted
                    // item is "Login in Browser" (EZ-Login). Send a bare
                    // Enter to accept it and continue into the browser
                    // flow — once per spawn so redraws don't re-fire.
                    if !self.didDismissAuthMenu,
                       Self.detectAuthMenuFooter(in: line) {
                        self.dismissAuthMenu()
                    }
                }
            }
            // The huh.Select footer is the last line of a TUI frame and is
            // usually redrawn WITHOUT a trailing newline, so extractLines()
            // never surfaces it. Probe the un-terminated tail too — the raw
            // bytes persist across reads, so a footer split mid-chunk is still
            // caught once fully buffered. dismissAuthMenu() is one-shot.
            let pending = buffer.peekPending()
            if !pending.isEmpty, Self.detectAuthMenuFooter(in: pending) {
                Task { @MainActor [weak self] in
                    guard let self, !self.didDismissAuthMenu else { return }
                    self.dismissAuthMenu()
                }
            }
        }

        do {
            try process.run()
        } catch {
            masterHandle.readabilityHandler = nil
            close(pty.slaveFD)
            newPTYMaster = nil
            lastError = "Couldn't launch slackdump: \(error.localizedDescription)"
            return
        }
        // Child owns its own dup'd copy now. Closing our slave reference
        // ensures the master sees EOF when the child exits.
        close(pty.slaveFD)
        runningNewProcess = process

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }
        runningNewProcess = nil
        newPTYMaster = nil
        masterHandle.readabilityHandler = nil
        let tail = masterHandle.availableData
        if !tail.isEmpty {
            buffer.append(tail)
            for (line, _) in buffer.extractLines() {
                newWorkspaceLog.append(line)
            }
        }
        if process.terminationStatus != 0 {
            lastError = "slackdump workspace new exited \(process.terminationStatus)."
        } else if let n = spawnedWorkspaceName {
            // Surface the new workspace name so the sheet can auto-select
            // it instead of making the user click "Select" themselves.
            lastAddedWorkspaceName = n
        }
        await refresh()
    }

    /// Called by the sheet once it has acted on `lastAddedWorkspaceName`,
    /// so the same workspace isn't re-selected on subsequent state changes.
    func acknowledgeLastAdded() {
        lastAddedWorkspaceName = nil
    }

    /// Accept slackdump's `huh.Select` auth picker by sending a bare Enter
    /// to the PTY master (selecting the default "Login in Browser"). One-shot
    /// — guarded by `didDismissAuthMenu` so TUI redraws can't re-fire it.
    private func dismissAuthMenu() {
        guard !didDismissAuthMenu else { return }
        didDismissAuthMenu = true
        guard let master = newPTYMaster else { return }
        try? master.write(contentsOf: Data([0x0D]))
        newWorkspaceLog.append(
            "[slacksucker] dismissed auth picker — selecting default (browser login)"
        )
    }

    /// Write a y/N answer to the running `workspace new` process by
    /// writing to the PTY master end and clear the pending-prompt flag.
    /// No-op if nothing is running.
    func answerOverwrite(yes: Bool) {
        guard let master = newPTYMaster else { return }
        let response = (yes ? "y\n" : "N\n").data(using: .utf8)!
        do {
            try master.write(contentsOf: response)
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

    /// Reduce a workspace identifier the user typed (URL or bare name)
    /// to the form slackdump v4.3 wants as the `workspace new` positional
    /// arg: just the first hostname label. `https://sheer-enterprise.slack.com/`
    /// → `sheer-enterprise`. A bare name passes through unchanged.
    nonisolated static func workspaceArg(from input: String) -> String {
        var s = input
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let r = s.firstIndex(of: "/") { s = String(s[..<r]) }
        if let r = s.firstIndex(of: ".") { s = String(s[..<r]) }
        s = s.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? input : s
    }

    /// Recognise slackdump's `huh.Select` keyhelp footer — distinctive
    /// enough to mean "we're sitting on the auth-method picker". The
    /// arrow + the word "submit" only co-occur on this footer; ANSI
    /// colouring between glyphs doesn't break the substring matches
    /// since each token sits inside its own colour run.
    nonisolated static func detectAuthMenuFooter(in line: String) -> Bool {
        line.contains("↑") && line.contains("submit")
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

    // MARK: - PTY allocation
    //
    // slackdump's EZ-Login refuses to start when stderr isn't a TTY
    // ("browser auth is not supported in dumb terminals, use token/cookie
    // auth instead."). Foundation's `Pipe` is an anonymous pipe and never
    // passes that isatty() check. Allocating a pseudo-terminal pair and
    // handing the slave end to the child satisfies the check; the master
    // end stays with us for read+write.

    /// Open a new PTY pair via the POSIX primitives. Returns `nil` on any
    /// failure; on success the caller owns both file descriptors.
    nonisolated static func openPTYPair() -> (masterFD: Int32, slaveFD: Int32)? {
        let m = posix_openpt(O_RDWR | O_NOCTTY)
        guard m >= 0 else { return nil }
        if grantpt(m) != 0 { close(m); return nil }
        if unlockpt(m) != 0 { close(m); return nil }
        guard let cname = ptsname(m) else { close(m); return nil }
        let s = open(cname, O_RDWR | O_NOCTTY)
        guard s >= 0 else { close(m); return nil }

        // Disable local echo on the slave so the y/N bytes we write to
        // the master end don't bounce back into the output log. Cosmetic
        // — slackdump still reads our input correctly either way.
        var t = termios()
        if tcgetattr(s, &t) == 0 {
            t.c_lflag &= ~tcflag_t(ECHO)
            _ = tcsetattr(s, TCSANOW, &t)
        }
        return (m, s)
    }
}
