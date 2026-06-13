import Foundation
import SwiftUI
import Combine
import UserNotifications

/// Discovers and owns the set of managed launchd jobs. Scans
/// `~/Library/LaunchAgents` for PhantomLives agents (see ``JobRegistry/shouldManage(label:)``),
/// builds one ``JobController`` per agent, refreshes them on a timer, and exposes
/// the worst-case health to drive the menu-bar glyph.
@MainActor
final class JobsModel: ObservableObject {

    @Published private(set) var jobs: [JobController] = []
    /// The job whose log/settings the secondary windows show.
    @Published var selectedJobID: String?

    private var timer: AnyCancellable?

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        rescan()
        Task { await refreshAll() }
        // Light periodic refresh so the menu-bar glyph + rows stay current, and
        // newly-installed agents appear without a relaunch.
        timer = Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in Task { await self?.tick() } }
    }

    private var launchAgentsDir: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents")
    }

    /// (Re)scan the LaunchAgents directory and reconcile the job list, preserving
    /// the live `JobController` for labels we already track.
    func rescan() {
        let dir = launchAgentsDir
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        var found: [JobController] = []
        for f in files where f.hasSuffix(".plist") {
            let path = (dir as NSString).appendingPathComponent(f)
            guard let d = LaunchAgentPlist.read(path: path), JobRegistry.shouldManage(label: d.label) else { continue }
            if let existing = jobs.first(where: { $0.id == d.label }) {
                found.append(existing)
            } else {
                found.append(JobController(descriptor: d))
            }
        }
        found.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        // Only reassign (and churn the views) when the set of labels actually changed.
        if found.map(\.id) != jobs.map(\.id) {
            jobs = found
        }
        if selectedJobID == nil || !jobs.contains(where: { $0.id == selectedJobID }) {
            selectedJobID = jobs.first?.id
        }
    }

    private func tick() async {
        rescan()
        await refreshAll()
    }

    func refreshAll() async {
        for j in jobs { await j.refresh() }
    }

    /// Worst health across all jobs → the menu-bar glyph. No jobs ⇒ attention.
    var aggregateHealth: SyncStatusParser.Health {
        jobs.map(\.health).max(by: { $0.severity < $1.severity }) ?? .warning
    }

    var selectedJob: JobController? {
        jobs.first { $0.id == selectedJobID }
    }
}
