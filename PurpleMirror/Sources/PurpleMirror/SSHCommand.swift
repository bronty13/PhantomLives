import Foundation

/// Builds the actual `(executable, arguments)` to run a command on a ``Host`` — unchanged for
/// the local host, wrapped in `ssh` for a remote one. PURE + unit-tested: the real `Process`
/// execution stays in `JobController.run`, so the entire local-vs-remote decision is testable
/// without touching the network.
enum SSHCommand {

    /// Shell-quote one argument for safe interpolation into a remote command string
    /// (single-quote wrap, with the standard `'\''` escape for embedded single quotes).
    static func shQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// ssh options used for every remote call. `BatchMode=yes` makes ssh *fail* rather than
    /// prompt (so a missing key never hangs the UI); `ConnectTimeout` bounds an unreachable/asleep
    /// host; ControlMaster multiplexing amortizes the handshake across the many small calls a
    /// refresh makes.
    static func sshOptions(for host: MonitoredHost) -> [String] {
        var opts = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=\(host.connectTimeout)",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=~/.ssh/cm-purplemirror-%r@%h:%p",
            "-o", "ControlPersist=120",
        ]
        if let key = host.identityFile, !key.isEmpty { opts += ["-i", key] }
        if host.port != 22 { opts += ["-p", String(host.port)] }
        return opts
    }

    /// The `(executable, arguments)` to run `launchPath args…` on `host`.
    /// - local → `(launchPath, args)` verbatim.
    /// - remote → `(/usr/bin/ssh, [options…, "--", target, "<quoted remote command>"])`.
    static func argv(for host: MonitoredHost, launchPath: String, args: [String]) -> (executable: String, arguments: [String]) {
        guard !host.isLocal else { return (launchPath, args) }
        let remoteCommand = ([launchPath] + args).map(shQuote).joined(separator: " ")
        let arguments = sshOptions(for: host) + ["--", host.sshTarget, remoteCommand]
        return ("/usr/bin/ssh", arguments)
    }

    /// The argv to run an arbitrary remote shell command string (e.g. `ls …`, `cat …`) on `host`.
    /// For the local host this returns a `/bin/sh -c` invocation so callers have one code path.
    static func shellArgv(for host: MonitoredHost, command: String) -> (executable: String, arguments: [String]) {
        if host.isLocal { return ("/bin/sh", ["-c", command]) }
        let arguments = sshOptions(for: host) + ["--", host.sshTarget, command]
        return ("/usr/bin/ssh", arguments)
    }
}
