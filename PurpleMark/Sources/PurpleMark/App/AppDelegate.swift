import AppKit

/// Routes Finder "open document" requests into the shared `AppState` and runs
/// the launch-time backup. PurpleMark is a single-window editor, so every open
/// replaces the current document (prompting to save if dirty).
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        BackupService.runOnLaunchIfDue(settings: AppSettings.shared)
    }

    /// Don't spawn a blank untitled document on every launch — the WindowGroup
    /// already provides the editor window.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor in
            maybeOpen(url)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        Task { @MainActor in
            maybeOpen(URL(fileURLWithPath: filename))
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    @MainActor
    private func maybeOpen(_ url: URL) {
        let state = AppState.shared
        guard state.isDirty else { state.open(url); return }
        let alert = NSAlert()
        alert.messageText = "Discard unsaved changes?"
        alert.informativeText = "“\(state.title)” has unsaved changes. Opening “\(url.lastPathComponent)” will discard them."
        alert.addButton(withTitle: "Save & Open")
        alert.addButton(withTitle: "Discard & Open")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if state.save() { state.open(url) }
        case .alertSecondButtonReturn:
            state.open(url)
        default:
            break
        }
    }
}
