import Foundation
import SwiftUI
import UserNotifications

/// Observable state + actions for ONE launchd background job. A thin GUI over the
/// job's launchd agent (and, for script-managed jobs, its install script) — the
/// script/plist remain the single source of truth; this never reimplements the
/// job's work. One `JobController` per agent discovered by ``JobsModel``.
@MainActor
final class JobController: ObservableObject, Identifiable {

    nonisolated var id: String { label }
    let label: String
    let profile: JobProfile

    @Published private(set) var descriptor: AgentDescriptor
    @Published private(set) var agentLoaded = false
    @Published private(set) var runs: Int?
    @Published private(set) var lastExitCode: Int?
    @Published private(set) var summary: SyncStatusParser.LogSummary?
    @Published private(set) var intervalSeconds: Int
    @Published private(set) var isRunning = false
    @Published private(set) var lastActionMessage: String?

    /// The `runs` count of the most recent failed run we've already alerted on,
    /// so a single failure produces a single notification (not one per refresh).
    private var notifiedForRun: Int?

    init(descriptor: AgentDescriptor) {
        self.label = descriptor.label
        self.descriptor = descriptor
        self.profile = JobRegistry.profile(for: descriptor)
        self.intervalSeconds = descriptor.startInterval ?? 3600
    }

    // MARK: Derived

    var displayName: String { profile.displayName }
    var intervalHuman: String { SyncStatusParser.humanizeInterval(intervalSeconds) }
    var lastActivityRelative: String { SyncStatusParser.relativeAge(of: summary?.date) }
    var scriptPath: String? { if case .script(let p, _) = profile.scheduling { return p } else { return descriptor.scriptPath } }

    private var plistPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    private var userDomain: String { "gui/\(getuid())" }
    private var domainTarget: String { "\(userDomain)/\(label)" }
    var logPath: String { profile.activityLogPathOverride ?? descriptor.stdoutPath ?? "" }

    var health: SyncStatusParser.Health {
        let base = SyncStatusParser.health(agentLoaded: agentLoaded, lastExitCode: lastExitCode, isSyncing: isRunning)
        // A recognized log-level failure (e.g. Rachel's "pull exit: 12", which the
        // wrapper script swallows so launchd still sees exit 0) downgrades health.
        if base == .healthy, summary?.ok == false { return .warning }
        return base
    }
    var menuBarSymbol: String { health.symbol }

    // MARK: Refresh

    func refresh() async {
        let (status, out) = await Self.run("/bin/launchctl", ["print", domainTarget])
        let agent = SyncStatusParser.parseAgentState(out, launchctlSucceeded: status == 0)

        // Re-read the plist so a hand-edited interval / args show up live.
        if let d = LaunchAgentPlist.read(path: plistPath) {
            descriptor = d
            intervalSeconds = d.startInterval ?? intervalSeconds
        }

        let logText = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
        if let sum = SyncStatusParser.summary(logText, kind: profile.logKind) { summary = sum }

        agentLoaded = agent.loaded
        runs = agent.runs
        lastExitCode = agent.lastExitCode

        if let code = agent.lastExitCode, code != 0, agent.runs != notifiedForRun {
            notifiedForRun = agent.runs
            postFailureNotification(exitCode: code)
        }
    }

    private func postFailureNotification(exitCode: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(displayName) failed"
        content.body = "The job reported an error (exit \(exitCode)). Open PurpleMirror ▸ View Log for details."
        content.sound = .default
        let req = UNNotificationRequest(identifier: "purplemirror-\(label)-failure-\(runs ?? 0)",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: Actions

    /// Trigger one run now. Uses the loaded agent (so the baked-in config is
    /// honored); falls back to the script / a bootstrap+kickstart if not loaded.
    func runNow() {
        guard !isRunning else { return }
        isRunning = true
        lastActionMessage = "Starting…"
        Task {
            var startedViaKickstart = true
            let result: (Int32, String)
            if agentLoaded {
                result = await Self.run("/bin/launchctl", ["kickstart", "-k", domainTarget])
            } else if case .script(let path, let envKeys) = profile.scheduling {
                startedViaKickstart = false
                result = await runScript(path, [], envKeys: envKeys)
            } else {
                _ = await Self.run("/bin/launchctl", ["bootstrap", userDomain, plistPath])
                result = await Self.run("/bin/launchctl", ["kickstart", "-k", domainTarget])
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await refresh()
            isRunning = false
            if result.0 != 0 {
                lastActionMessage = "Run failed to start (see log)"
            } else if startedViaKickstart {
                lastActionMessage = "Run started — watch the log"
            } else {
                lastActionMessage = "Ran \(lastActivityRelative)"
            }
        }
    }

    func enable() {
        Task {
            lastActionMessage = "Enabling…"
            switch profile.scheduling {
            case .script(let path, let envKeys):
                _ = await runScript(path, ["--install-agent", String(intervalSeconds)], envKeys: envKeys)
            case .plist:
                _ = await Self.run("/bin/launchctl", ["bootstrap", userDomain, plistPath])
            }
            await refresh()
            lastActionMessage = "Auto-run enabled"
        }
    }

    func disable() {
        Task {
            lastActionMessage = "Disabling…"
            switch profile.scheduling {
            case .script(let path, _):
                _ = await runScript(path, ["--uninstall-agent"], envKeys: [])
            case .plist:
                // Leave the plist file on disk so it can be re-enabled; just unload it.
                _ = await Self.run("/bin/launchctl", ["bootout", domainTarget])
            }
            await refresh()
            lastActionMessage = "Auto-run disabled (manual only)"
        }
    }

    func setInterval(_ seconds: Int) {
        Task {
            lastActionMessage = "Updating schedule…"
            switch profile.scheduling {
            case .script(let path, let envKeys):
                _ = await runScript(path, ["--install-agent", String(seconds)], envKeys: envKeys)
            case .plist:
                await setPlistInterval(seconds)
            }
            await refresh()
            lastActionMessage = "Schedule: every \(SyncStatusParser.humanizeInterval(seconds))"
        }
    }

    // MARK: Plist interval edit (defensive)

    /// Rewrite ONLY `StartInterval` in the agent's plist, then reload it. Keeps a
    /// backup and restores it if the reload fails, so an operational plist (e.g.
    /// Rachel's photo-sync) can't be left broken.
    private func setPlistInterval(_ seconds: Int) async {
        guard let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any] else {
            lastActionMessage = "Couldn't read \(label).plist"; return
        }
        let updated = LaunchAgentPlist.withStartInterval(dict, seconds: seconds)

        let backup = plistPath + ".purplemirror.bak"
        let fm = FileManager.default
        try? fm.removeItem(atPath: backup)
        try? fm.copyItem(atPath: plistPath, toPath: backup)

        guard (updated as NSDictionary).write(toFile: plistPath, atomically: true) else {
            lastActionMessage = "Couldn't write \(label).plist"
            try? fm.removeItem(atPath: backup)
            return
        }

        _ = await Self.run("/bin/launchctl", ["bootout", domainTarget])
        let (st, _) = await Self.run("/bin/launchctl", ["bootstrap", userDomain, plistPath])
        if st != 0 {
            // Restore and re-bootstrap the previous config.
            try? fm.removeItem(atPath: plistPath)
            try? fm.copyItem(atPath: backup, toPath: plistPath)
            _ = await Self.run("/bin/launchctl", ["bootstrap", userDomain, plistPath])
            lastActionMessage = "Reload failed — restored previous schedule"
        }
        try? fm.removeItem(atPath: backup)
    }

    // MARK: Log access

    func readLog() -> String {
        guard !logPath.isEmpty else { return "(this job has no log path)" }
        return (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? "(no log yet at \(logPath))"
    }

    func revealLogInFinder() {
        guard !logPath.isEmpty else { return }
        NSWorkspace.shared.selectFile(logPath, inFileViewerRootedAtPath: "")
    }

    func openLogInConsole() {
        guard !logPath.isEmpty else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: logPath)],
                                withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Process plumbing

    /// Run a script via /bin/bash, carrying over the requested env keys from the
    /// installed plist (e.g. OBSIDIAN_VAULT so --install-agent re-bakes it).
    private func runScript(_ path: String, _ args: [String], envKeys: [String]) async -> (Int32, String) {
        var env = ProcessInfo.processInfo.environment
        for k in envKeys { if let v = descriptor.environment[k], !v.isEmpty { env[k] = v } }
        return await Self.run("/bin/bash", [path] + args, env: env)
    }

    /// Run a command off the main actor; capture merged stdout+stderr.
    nonisolated static func run(_ launchPath: String, _ args: [String],
                                env: [String: String]? = nil) async -> (Int32, String) {
        await Task.detached(priority: .userInitiated) { () -> (Int32, String) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: launchPath)
            proc.arguments = args
            if let env { proc.environment = env }
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            do {
                try proc.run()
            } catch {
                return (-1, "failed to launch \(launchPath): \(error.localizedDescription)")
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }.value
    }
}
