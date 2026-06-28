import Foundation
import SwiftUI
import Combine
import UserNotifications

/// Discovers and owns the set of managed launchd jobs across one or more hosts (the local Mac plus
/// any remote runners from ``HostStore``). For each host it lists `~/Library/LaunchAgents`, keeps
/// the PhantomLives agents (see ``JobRegistry/shouldManage(label:)``), builds one ``JobController``
/// per (host, agent), refreshes them on a timer, and exposes the worst-case health for the menu-bar
/// glyph. With only the local host this behaves exactly as PurpleMirror always has.
@MainActor
final class JobsModel: ObservableObject {

    @Published private(set) var jobs: [JobController] = []
    /// The job whose log/settings the secondary windows show.
    @Published var selectedJobID: String?

    private(set) var hostContexts: [HostContext]
    private var timer: AnyCancellable?
    private var jobObservers: [String: AnyCancellable] = [:]
    /// Re-list agents (discovery) less often than we refresh state, to keep ssh chatter down.
    private var tickCount = 0
    private let rescanEveryTicks = 6   // refresh every 10s; re-discover ~every 60s

    var monitoredHosts: [MonitoredHost] { hostContexts.map(\.host) }
    var hasRemoteHosts: Bool { hostContexts.contains { !$0.host.isLocal } }

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        self.hostContexts = HostStore.allHosts().map { HostContext(host: $0) }
        Task { await rescan(); await refreshAll() }
        // Light periodic refresh so the menu-bar glyph + rows stay current, and
        // newly-installed agents appear without a relaunch.
        timer = Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in Task { await self?.tick() } }
    }

    /// Rebuild host contexts from the persisted host list (after the user edits Settings ▸ Hosts),
    /// preserving any existing context whose host is unchanged (keeps its resolved uid/home).
    func reloadHosts() {
        objectWillChange.send()   // host list (monitoredHosts) is derived from hostContexts
        let hosts = HostStore.allHosts()
        hostContexts = hosts.map { h in
            hostContexts.first(where: { $0.host == h }) ?? HostContext(host: h)
        }
        Task { await rescan(); await refreshAll() }
    }

    /// (Re)scan every host's LaunchAgents directory and reconcile the job list, preserving the
    /// live `JobController` for (host, label) pairs we already track. An unreachable remote host
    /// keeps its last-known jobs (marked unreachable on refresh) rather than dropping them.
    func rescan() async {
        var found: [JobController] = []
        for ctx in hostContexts {
            let hostID = ctx.host.id
            if !ctx.host.isLocal {
                await ctx.ensureResolved()
                guard ctx.reachable else {
                    found.append(contentsOf: jobs.filter { $0.host.id == hostID })
                    continue
                }
            }
            await ctx.refreshIP()   // track the host's live IP (local + reachable remotes)
            let paths = await ctx.listLaunchAgentPlists()
            if !ctx.host.isLocal && !ctx.reachable {
                found.append(contentsOf: jobs.filter { $0.host.id == hostID })
                continue
            }
            for path in paths {
                guard let d = await ctx.readPlist(path: path), JobRegistry.shouldManage(label: d.label) else { continue }
                let jid = "\(hostID)/\(d.label)"
                if let existing = jobs.first(where: { $0.id == jid }) {
                    found.append(existing)
                } else {
                    let jc = JobController(descriptor: d, ctx: ctx)
                    jobObservers[jid] = jc.objectWillChange.sink { [weak self] _ in
                        self?.objectWillChange.send()
                    }
                    found.append(jc)
                }
            }
        }
        // Stable order: local host first, then by host name, then job name.
        found.sort {
            if $0.isLocalHost != $1.isLocalHost { return $0.isLocalHost }
            if $0.hostName != $1.hostName { return $0.hostName.localizedCaseInsensitiveCompare($1.hostName) == .orderedAscending }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        jobObservers = jobObservers.filter { key, _ in found.contains { $0.id == key } }
        if found.map(\.id) != jobs.map(\.id) { jobs = found }
        if selectedJobID == nil || !jobs.contains(where: { $0.id == selectedJobID }) {
            selectedJobID = jobs.first?.id
        }
    }

    private func tick() async {
        tickCount += 1
        if tickCount % rescanEveryTicks == 0 { await rescan() }
        // Backoff: a failing remote host is probed progressively less often (it doesn't burn an
        // ssh ConnectTimeout every tick), while healthy/local hosts refresh every tick.
        let probe = Set(hostContexts
            .filter { $0.host.isLocal || Backoff.shouldProbe(consecutiveFailures: $0.consecutiveFailures, tick: tickCount) }
            .map(\.host.id))
        await refresh(hostIDs: probe)
    }

    /// User-initiated full refresh — try every host regardless of backoff.
    func refreshAll() async { await refresh(hostIDs: Set(hostContexts.map(\.host.id))) }

    /// Refresh the jobs on the given hosts concurrently, so a slow/asleep remote can't stall others.
    private func refresh(hostIDs: Set<String>) async {
        await withTaskGroup(of: Void.self) { group in
            for j in jobs where hostIDs.contains(j.hostID) { group.addTask { await j.refresh() } }
        }
    }

    /// Remote hosts currently unreachable, with a "last seen" string for the offline banner.
    var offlineHosts: [(host: MonitoredHost, lastSeen: String)] {
        hostContexts.filter { !$0.host.isLocal && !$0.reachable }
            .map { ($0.host, $0.lastSeenRelative) }
    }

    /// Worst health across all jobs → the menu-bar glyph. No jobs ⇒ attention.
    var aggregateHealth: SyncStatusParser.Health {
        jobs.map(\.health).max(by: { $0.severity < $1.severity }) ?? .warning
    }

    /// Jobs grouped for display. With more than one host the group name is prefixed with the host
    /// (e.g. "Runner · Photos") so host blocks stay contiguous; single-host display is unchanged.
    var groups: [(name: String, jobs: [JobController])] {
        let multi = hostContexts.count > 1
        var m: [String: [JobController]] = [:]
        for j in jobs {
            let key = multi ? "\(j.hostName) · \(j.group)" : j.group
            m[key, default: []].append(j)
        }
        func rank(_ g: String) -> Int { (g.hasSuffix("Obsidian") || g.hasSuffix("Other")) ? 1 : 0 }
        return m.keys.sorted {
            rank($0) != rank($1) ? rank($0) < rank($1)
                                 : $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }.map { name in
            (name, m[name]!.sorted { $0.shortName.localizedCaseInsensitiveCompare($1.shortName) == .orderedAscending })
        }
    }

    func groupHealth(_ js: [JobController]) -> SyncStatusParser.Health {
        js.map(\.health).max(by: { $0.severity < $1.severity }) ?? .healthy
    }

    /// New items found across all jobs in the last 24h (jobs without a "new items" concept,
    /// e.g. the Obsidian mirror, are excluded).
    var totalItemsLast24h: Int { jobs.compactMap(\.itemsLast24h).reduce(0, +) }

    func groupItemsLast24h(_ js: [JobController]) -> Int { js.compactMap(\.itemsLast24h).reduce(0, +) }

    var selectedJob: JobController? {
        jobs.first { $0.id == selectedJobID }
    }
}
