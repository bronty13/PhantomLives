import Foundation
import SwiftUI
import Combine

/// A single global timer. `start(matterId:)` ends any previous active session
/// (so two sessions can never run at once and double-bill) and persists the
/// active state to settings so a relaunch can offer to resume.
@MainActor
final class TimerService: ObservableObject {
    @Published private(set) var activeMatterId: String?
    @Published private(set) var startedAt: Date?
    /// Drives a once-per-second redraw of any view that displays the running
    /// elapsed time. Views subscribe via `@ObservedObject`.
    @Published private(set) var tick: Date = Date()

    private weak var settingsStore: SettingsStore?
    private weak var appState: AppState?
    private var timer: Timer?

    init(settingsStore: SettingsStore, appState: AppState) {
        self.settingsStore = settingsStore
        self.appState = appState
        // Resume from a persisted active session if the app was force-quit
        // mid-timer. We don't re-start the wall clock from scratch — the
        // original `started_at` is preserved so the elapsed count is accurate.
        let s = settingsStore.settings
        if !s.activeTimerMatterId.isEmpty,
           let start = parseISO(s.activeTimerStartedAt) {
            activeMatterId = s.activeTimerMatterId
            startedAt = start
            startTickingLoop()
        }
    }

    var elapsedSeconds: Int {
        guard let startedAt else { return 0 }
        return max(0, Int(tick.timeIntervalSince(startedAt)))
    }

    func start(matterId: String) {
        if activeMatterId == matterId { return }
        if activeMatterId != nil { stop() }
        activeMatterId = matterId
        startedAt = Date()
        persistActive()
        startTickingLoop()
        // Status auto-transition: lift "New" Matters to "In-Progress" when
        // the first time entry begins. Silent if the lifecycle has been
        // renamed — we look up by sort_order, not literal name.
        appState?.bumpToInProgressIfNew(matterId: matterId)
    }

    @discardableResult
    func stop(note: String = "") -> TimeEntry? {
        guard let matterId = activeMatterId, let started = startedAt else { return nil }
        let now = Date()
        let seconds = max(0, Int(now.timeIntervalSince(started)))
        let entry = TimeEntry(
            id: UUID().uuidString,
            matterId: matterId,
            startedAt: started,
            endedAt: now,
            seconds: seconds,
            note: note
        )
        try? DatabaseService.shared.insertTimeEntry(entry)
        activeMatterId = nil
        startedAt = nil
        persistActive()
        timer?.invalidate()
        timer = nil
        appState?.reloadTimeEntries()
        return entry
    }

    private func startTickingLoop() {
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick = Date() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func persistActive() {
        guard let store = settingsStore else { return }
        var s = store.settings
        s.activeTimerMatterId = activeMatterId ?? ""
        s.activeTimerStartedAt = startedAt.map { isoString(from: $0) } ?? ""
        store.settings = s
        store.save()
    }

    private func isoString(from date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: date)
    }
    private func parseISO(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: s)
    }
}

/// Format helpers used throughout the time UI.
enum TimeFormat {
    static func hms(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    /// Friendly hours+minutes — used in summaries where seconds aren't useful.
    static func hm(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
