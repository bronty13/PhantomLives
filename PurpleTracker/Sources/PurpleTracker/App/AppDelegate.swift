import AppKit
import SwiftUI
import Combine

/// Hosts the menu-bar mini-timer (NSStatusItem) — visible from anywhere on
/// the system so the user can see at a glance that the timer is running and
/// click to stop it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func installMenuBarItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⏸ —"
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        statusItem = item
        startObserving()
    }

    private func startObserving() {
        guard let app = appState else { return }
        // Refresh on every TimerService.tick (1Hz when running) and on
        // selection changes so the title reflects which matter is active.
        app.timer.$tick.sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        app.timer.$activeMatterId.sink { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        refresh()
    }

    private func refresh() {
        guard let app = appState, let button = statusItem?.button else { return }
        if let id = app.timer.activeMatterId,
           let m = app.matters.first(where: { $0.id == id }) {
            let secs = app.timer.elapsedSeconds
            let label = m.title.isEmpty ? m.id : m.title
            let trimmed = label.count > 24 ? String(label.prefix(22)) + "…" : label
            button.title = "⏱ \(TimeFormat.hm(secs)) — \(trimmed)"
        } else {
            button.title = "⏸ PurpleTracker"
        }
    }

    @objc private func statusItemClicked() {
        guard let app = appState else { return }
        if app.timer.activeMatterId != nil {
            _ = app.timer.stop()
        } else if let id = app.selectedMatterId {
            app.timer.start(matterId: id)
        }
        // Bring the main window forward in either case.
        NSApp.activate(ignoringOtherApps: true)
    }
}
