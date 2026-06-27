import Foundation
import SwiftUI
import UserNotifications

/// Observable state + actions for ONE launchd background job on ONE host. A thin GUI over the
/// job's launchd agent (and, for script-managed jobs, its install script) — the script/plist
/// remain the single source of truth; this never reimplements the job's work. One
/// `JobController` per (host, agent) discovered by ``JobsModel``.
///
/// All execution + I/O flows through the job's ``HostContext`` (local verbatim, or ssh-wrapped),
/// so the same controller drives a local job or one on the remote runner. Schedule edits
/// (enable/disable/interval) are local-only for now; remote control is limited to Run-Now.
@MainActor
final class JobController: ObservableObject, Identifiable {

    /// Unique across hosts (the same label can run on Vortex AND the runner — e.g. brew-autoupdate).
    /// Built from plain `let`s so it's safe to read from a nonisolated context (Identifiable).
    nonisolated var id: String { "\(hostID)/\(label)" }
    let hostID: String
    let label: String
    let profile: JobProfile
    let ctx: HostContext
    var host: MonitoredHost { ctx.host }

    @Published private(set) var descriptor: AgentDescriptor
    @Published private(set) var agentLoaded = false
    @Published private(set) var runs: Int?
    @Published private(set) var lastExitCode: Int?
    @Published private(set) var summary: SyncStatusParser.LogSummary?
    /// New items this job found/archived in the last 24h (nil = no "new items" concept, e.g. mirror).
    @Published private(set) var itemsLast24h: Int?
    @Published private(set) var intervalSeconds: Int
    @Published private(set) var isRunning = false
    @Published private(set) var lastActionMessage: String?
    /// False when this job's (remote) host couldn't be reached on the last refresh.
    @Published private(set) var hostReachable = true

    /// The `runs` count of the most recent failed run we've already alerted on,
    /// so a single failure produces a single notification (not one per refresh).
    private var notifiedForRun: Int?

    init(descriptor: AgentDescriptor, ctx: HostContext) {
        self.label = descriptor.label
        self.hostID = ctx.host.id
        self.descriptor = descriptor
        self.ctx = ctx
        self.profile = JobRegistry.profile(for: descriptor)
        self.intervalSeconds = descriptor.startInterval ?? 3600
    }

    // MARK: Derived

    var displayName: String { profile.displayName }
    var group: String { profile.group }
    var shortName: String { profile.shortName.isEmpty ? profile.displayName : profile.shortName }
    var intervalHuman: String { SyncStatusParser.humanizeInterval(intervalSeconds) }
    var lastActivityRelative: String { SyncStatusParser.relativeAge(of: summary?.date) }
    var scriptPath: String? { if case .script(let p, _) = profile.scheduling { return p } else { return descriptor.scriptPath } }

    /// Host this job lives on (for UI attribution when more than one host is monitored).
    var hostName: String { host.displayName }
    var isLocalHost: Bool { host.isLocal }

    private var plistPath: String { ctx.home + "/Library/LaunchAgents/\(label).plist" }
    private var userDomain: String { "gui/\(ctx.uid)" }
    private var domainTarget: String { "\(userDomain)/\(label)" }

    /// The activity log path on this job's host. A profile override is built against the LOCAL
    /// home, so for a remote host it's rebased onto that host's home; otherwise the plist's own
    /// `StandardOutPath` (already absolute on the remote) is used.
    var logPath: String { rebaseHome(profile.activityLogPathOverride) ?? descriptor.stdoutPath ?? "" }

    private func rebaseHome(_ path: String?) -> String? {
        guard let path else { return nil }
        guard !host.isLocal else { return path }
        let localHome = NSHomeDirectory()
        if path.hasPrefix(localHome) { return ctx.home + String(path.dropFirst(localHome.count)) }
        return path
    }

    var health: SyncStatusParser.Health {
        if !hostReachable { return .warning }
        let base = SyncStatusParser.health(agentLoaded: agentLoaded, lastExitCode: lastExitCode, isSyncing: isRunning)
        // A recognized log-level failure (e.g. a PurpleAttic sync's "pull exit: 12",
        // which the wrapper script swallows so launchd still sees exit 0) downgrades health.
        if base == .healthy, summary?.ok == false { return .warning }
        return base
    }
    var menuBarSymbol: String { health.symbol }

    // MARK: Refresh

    func refresh() async {
        if !host.isLocal { await ctx.ensureResolved() }
        guard ctx.reachable else {
            hostReachable = false
            return
        }
        let (status, out) = await ctx.run("/bin/launchctl", ["print", domainTarget])
        let agent = SyncStatusParser.parseAgentState(out, launchctlSucceeded: status == 0)

        // Re-read the plist so a hand-edited interval / args show up live.
        if let d = await ctx.readPlist(path: plistPath) {
            descriptor = d
            intervalSeconds = d.startInterval ?? intervalSeconds
        }

        let logText = await ctx.readText(path: logPath) ?? ""
        if let sum = SyncStatusParser.summary(logText, kind: profile.logKind) { summary = sum }
        itemsLast24h = SyncStatusParser.itemsLast24h(logText, kind: profile.logKind)

        hostReachable = ctx.reachable
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
        content.title = "\(displayName) failed\(host.isLocal ? "" : " on \(hostName)")"
        content.body = "The job reported an error (exit \(exitCode)). Open PurpleMirror ▸ View Log for details."
        content.sound = .default
        let req = UNNotificationRequest(identifier: "purplemirror-\(id)-failure-\(runs ?? 0)",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: Actions

    /// Trigger one run now. For a loaded agent this is a `launchctl kickstart` — which works on
    /// the local Mac OR the remote runner (the only control that needs no local paths). For an
    /// *un*loaded agent the local fallbacks (script / bootstrap) only apply on the local host;
    /// on a remote host, enable it there first.
    func runNow() {
        guard !isRunning else { return }
        if !host.isLocal && !agentLoaded {
            lastActionMessage = "Not loaded on \(hostName) — enable it there first"
            return
        }
        isRunning = true
        lastActionMessage = "Starting…"
        Task {
            var startedViaKickstart = true
            let result: (Int32, String)
            if agentLoaded {
                result = await ctx.run("/bin/launchctl", ["kickstart", "-k", domainTarget])
            } else if case .script(let path, let envKeys) = profile.scheduling {
                startedViaKickstart = false
                result = await runScript(path, [], envKeys: envKeys)
            } else {
                _ = await ctx.run("/bin/launchctl", ["bootstrap", userDomain, plistPath])
                result = await ctx.run("/bin/launchctl", ["kickstart", "-k", domainTarget])
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

    /// True when schedule edits (enable/disable/interval) are available — local host only for now.
    var canEditSchedule: Bool { host.isLocal }

    func enable() {
        guard requireLocalForScheduleEdit() else { return }
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
        guard requireLocalForScheduleEdit() else { return }
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
        guard requireLocalForScheduleEdit() else { return }
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

    /// Phase 2 limits schedule edits to the local host (they need local plist/script paths).
    /// Remote control beyond Run-Now is a later phase.
    private func requireLocalForScheduleEdit() -> Bool {
        if host.isLocal { return true }
        lastActionMessage = "Schedule edits on \(hostName) aren't supported yet — Run Now works"
        return false
    }

    // MARK: Plist interval edit (defensive, local only)

    /// Rewrite ONLY `StartInterval` in the agent's plist, then reload it. Keeps a
    /// backup and restores it if the reload fails, so an operational plist (e.g. a
    /// PurpleAttic external-source sync) can't be left broken.
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

    /// Fetch the job's log (host-aware: local read or `cat` over ssh).
    func loadLog() async -> String {
        guard !logPath.isEmpty else { return "(this job has no log path)" }
        if !host.isLocal { await ctx.ensureResolved() }
        return await ctx.readText(path: logPath) ?? "(no log yet at \(logPath))"
    }

    /// Reveal / open-in-Console only make sense for a local file.
    var hasLocalLog: Bool { host.isLocal && !logPath.isEmpty }

    func revealLogInFinder() {
        guard hasLocalLog else { return }
        NSWorkspace.shared.selectFile(logPath, inFileViewerRootedAtPath: "")
    }

    func openLogInConsole() {
        guard hasLocalLog else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: logPath)],
                                withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Process plumbing

    /// Run a script via /bin/bash on the LOCAL host, carrying over the requested env keys from the
    /// installed plist (e.g. OBSIDIAN_VAULT so --install-agent re-bakes it). Only reached on the
    /// local host (schedule edits are local-only).
    private func runScript(_ path: String, _ args: [String], envKeys: [String]) async -> (Int32, String) {
        var env = ProcessInfo.processInfo.environment
        for k in envKeys { if let v = descriptor.environment[k], !v.isEmpty { env[k] = v } }
        return await Self.run("/bin/bash", [path] + args, env: env)
    }

    /// Run a command off the main actor; capture merged stdout+stderr. The one `Process` runner;
    /// ``HostContext`` reuses it for both local and ssh-wrapped invocations.
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
