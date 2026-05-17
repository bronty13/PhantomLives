import SwiftUI

@main
struct PurpleReelApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("PurpleReel") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .defaultSize(width: 1400, height: 900)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Folder…") { appState.chooseRootFolder() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .windowArrangement) {
                Button("Reset Window State…") {
                    let alert = NSAlert()
                    alert.messageText = "Reset Window State?"
                    alert.informativeText = "Sidebar, window size, and split positions will return to defaults. Restart PurpleReel after confirming for the change to take full effect."
                    alert.addButton(withTitle: "Reset")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        WindowStateGuard.forceReset(
                            appName: "PurpleReel",
                            resetVersion: AppDelegate.windowResetVersion
                        )
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(minWidth: 640, minHeight: 420)
        }
    }
}
