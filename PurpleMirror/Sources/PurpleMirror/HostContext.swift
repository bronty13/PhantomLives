import Foundation

/// Per-host execution + I/O. Encapsulates everything that differs between the local Mac and a
/// remote SSH host, so ``JobController`` / ``JobsModel`` stay host-agnostic. The local context is
/// behavior-identical to PurpleMirror's original direct-FileManager / `getuid()` / local-`Process`
/// path; a remote context routes the same operations through `ssh` (see ``SSHCommand``).
///
/// Resolves the host's `uid` + `$HOME` once (needed to address `gui/<uid>/<label>` and to rebase
/// home-relative log/plist paths onto the remote home), and tracks reachability so an asleep /
/// offline runner degrades gracefully instead of stalling the refresh.
@MainActor
final class HostContext: ObservableObject {
    let host: MonitoredHost
    @Published private(set) var reachable: Bool
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
        } else {
            self.uid = -1
            self.home = ""
            self.resolved = false
            self.reachable = false
        }
    }

    /// Resolve `uid` + `$HOME` for a remote host (no-op for local). Updates `reachable`.
    /// Must succeed before remote discovery (paths are built from `home`).
    func ensureResolved() async {
        guard !host.isLocal, !resolved else { return }
        let (st, out) = await shell("id -u; echo \"$HOME\"")
        let lines = out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        if st == 0, lines.count >= 2, let u = Int(lines[0]), !lines[1].isEmpty {
            uid = u; home = lines[1]; resolved = true; reachable = true
        } else {
            reachable = false
        }
    }

    // MARK: Execution

    /// Run `launchPath args…` on this host (local verbatim, or ssh-wrapped). Reuses the one
    /// `Process` runner in ``JobController/run(_:_:env:)``.
    func run(_ launchPath: String, _ args: [String], env: [String: String]? = nil) async -> (Int32, String) {
        let (exe, a) = SSHCommand.argv(for: host, launchPath: launchPath, args: args)
        return await JobController.run(exe, a, env: env)
    }

    /// Run a shell command string on this host (`/bin/sh -c` locally, or over ssh).
    func shell(_ command: String) async -> (Int32, String) {
        let (exe, a) = SSHCommand.shellArgv(for: host, command: command)
        return await JobController.run(exe, a)
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
        guard st == 0 else { reachable = false; return [] }
        reachable = true
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
