import AppKit

/// Routes Finder "open document" requests into the shared `AppState`, runs the
/// launch-time backup, guards quit against unsaved changes, and persists /
/// restores the tab session. PurpleMark is a single-window editor.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let didPromptDefaultKey = "hasPromptedDefaultHandler"

    func applicationDidFinishLaunching(_ notification: Notification) {
        BackupService.runOnLaunchIfDue(settings: AppSettings.shared)
        AppState.shared.restoreSession()
        maybePromptToSetAsDefault()
    }

    /// Quitting with unsaved changes used to discard them silently — walk the
    /// dirty tabs and offer Save / Discard / Cancel for each.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let state = AppState.shared
        for doc in state.documents where doc.isDirty {
            state.activate(doc)
            let alert = NSAlert()
            alert.messageText = "Save changes to “\(doc.title)” before quitting?"
            alert.informativeText = "Your changes will be lost if you don't save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Discard")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                if !doc.save() { return .terminateCancel }   // save cancelled/failed
            case .alertSecondButtonReturn:
                continue
            default:
                return .terminateCancel
            }
        }
        AppState.shared.persistSession()
        return .terminateNow
    }

    /// On first launch, offer to make PurpleMark the default `.md` editor —
    /// once only (either choice records that we've asked, so it never nags).
    private func maybePromptToSetAsDefault() {
        guard !UserDefaults.standard.bool(forKey: didPromptDefaultKey) else { return }
        if DefaultHandlerService.isDefault() {
            UserDefaults.standard.set(true, forKey: didPromptDefaultKey)
            return
        }
        // Delay so the main window is on screen before the sheet-style alert.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [didPromptDefaultKey] in
            let alert = NSAlert()
            alert.messageText = "Make PurpleMark your default Markdown editor?"
            alert.informativeText = "Double-clicking .md files in Finder will open them in PurpleMark, and Quick Look (spacebar) will use PurpleMark's preview. You can change this anytime in Settings → Default Application."
            alert.addButton(withTitle: "Set as Default")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn {
                DefaultHandlerService.setAsDefault { _ in }
            }
            UserDefaults.standard.set(true, forKey: didPromptDefaultKey)
        }
    }

    /// Don't spawn a blank untitled document on every launch — the Window
    /// scene already provides the editor window.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { AppState.shared.open(url) }   // each opens/focuses a tab
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        AppState.shared.open(URL(fileURLWithPath: filename))
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}
