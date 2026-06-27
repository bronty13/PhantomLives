import Foundation

/// Per-host execution + I/O. Encapsulates everything that differs between the local Mac and a
/// remote SSH host, so ``JobController`` / ``JobsModel`` stay host-agnostic. The local context is
/// behavior-identical to PurpleMirror's original direct-FileManager / `getuid()` / local-`Process`
/// path; a remote context routes the same operations through `ssh` (see ``SSHCommand``).
///
/// Resolves the host's `uid` + `$HOME` once (needed to address `gui/<uid>/<label>` and to rebase
/// home-relative log/plist paths onto the remote home), and tracks **live reachability** — every
/// remote call updates it (ssh exit 255 = couldn't connect), so a runner that goes to sleep mid-
/// session is detected and (via ``JobsModel`` backoff) probed less often instead of stalling.
@MainActor
final class HostContext: ObservableObject {
    let host: MonitoredHost
    @Published private(set) var reachable: Bool
    /// Consecutive failed probes (0 when healthy) — drives ``JobsModel`` retry backoff.
    private(set) var consecutiveFailures = 0
    /// When the host was last reached successfully (nil if never).
    @Published private(set) var lastSeen: Date?

    private(set) var uid: Int
    private(set) var home: String
    private var resolved: Bool

    init(host: MonitoredHost) {
        self.host = host
        if host.isLocal {
            self.uid = Int(getuid())
            self.home = NSHomeDirectory()
            self.resolved = true
            self.reachable = true
            self.lastSeen = Date()
        } else {
            self.uid = -1
            self.home = ""
            self.resolved = false
            self.reachable = false
        }
    }

    /// "5m ago" / "just now" for the last successful contact (or "never").
    var lastSeenRelative: String { lastSeen == nil ? "never" : SyncStatusParser.relativeAge(of: lastSeen) }

    /// Record the outcome of a remote call. ssh exits 255 when it can't establish the connection
    /// (and our runner returns -1 if `/usr/bin/ssh` itself fails to launch) — anything else means
    /// we reached the host, even if the command itself returned non-zero.
    private func markReachable(_ ok: Bool) {
        reachable = ok
        if ok { consecutiveFailures = 0; lastSeen = Date() }
        else { consecutiveFailures += 1 }
    }

    /// Resolve `uid` + `$HOME` for a remote host (no-op for local; lazy until first reachable).
    func ensureResolved() async {
        guard !host.isLocal, !resolved else { return }
        let (st, out) = await shell("id -u; echo \"$HOME\"")   // shell() updates reachability
        let lines = out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        if st == 0, lines.count >= 2, let u = Int(lines[0]), !lines[1].isEmpty {
            uid = u; home = lines[1]; resolved = true
        }
    }

    // MARK: Execution

    /// Run `launchPath args…` on this host (local verbatim, or ssh-wrapped). Reuses the one
    /// `Process` runner in ``JobController/run(_:_:env:)`` and updates live reachability.
    func run(_ launchPath: String, _ args: [String], env: [String: String]? = nil) async -> (Int32, String) {
        let (exe, a) = SSHCommand.argv(for: host, launchPath: launchPath, args: args)
        let r = await JobController.run(exe, a, env: env)
        if !host.isLocal { markReachable(r.0 != 255 && r.0 != -1) }
        return r
    }

    /// Run a shell command string on this host (`/bin/sh -c` locally, or over ssh).
    func shell(_ command: String) async -> (Int32, String) {
        let (exe, a) = SSHCommand.shellArgv(for: host, command: command)
        let r = await JobController.run(exe, a)
        if !host.isLocal { markReachable(r.0 != 255 && r.0 != -1) }
        return r
    }

    // MARK: I/O

    /// Read a text file (local direct read, or `cat` over ssh). Nil if missing/unreadable.
    func readText(path: String) async -> String? {
        guard !path.isEmpty else { return nil }
        if host.isLocal { return try? String(contentsOfFile: path, encoding: .utf8) }
        let (st, out) = await shell("cat \(SSHCommand.shQuote(path))")
        return st == 0 ? out : nil
    }

    /// Full paths of every `*.plist` in `~/Library/LaunchAgents` on this host.
    func listLaunchAgentPlists() async -> [String] {
        let dir = home + "/Library/LaunchAgents"
        if host.isLocal {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            return files.filter { $0.hasSuffix(".plist") }.map { (dir as NSString).appendingPathComponent($0) }
        }
        let (st, out) = await shell("ls -1 \(SSHCommand.shQuote(dir)) 2>/dev/null")
        guard st == 0 else { return [] }
        return out.split(separator: "\n").map(String.init)
            .filter { $0.hasSuffix(".plist") }
            .map { dir + "/" + $0 }
    }

    /// Parse a LaunchAgent plist on this host. Remote uses `plutil -convert xml1 -o -` so the
    /// bytes come back utf8-safe (a binary plist over a text channel would corrupt).
    func readPlist(path: String) async -> AgentDescriptor? {
        if host.isLocal { return LaunchAgentPlist.read(path: path) }
        let (st, out) = await shell("plutil -convert xml1 -o - \(SSHCommand.shQuote(path))")
        guard st == 0 else { return nil }
        return LaunchAgentPlist.parse(data: Data(out.utf8))
    }
}
