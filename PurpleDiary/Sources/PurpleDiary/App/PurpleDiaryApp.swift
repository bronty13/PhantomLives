import SwiftUI
import AppKit

/// `App` entry point. Constructs the singleton `AppState` (which fires the
/// launch-time backup before any UI reads the DB), wires the main
/// `WindowGroup` and the separate `Settings` scene. The window-state guard is
/// applied from `AppDelegate.applicationWillFinishLaunching` (before the first
/// window materializes).
@main
struct PurpleDiaryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1000, minHeight: 640)
                .tint(appState.effectiveAccentColor)
                .preferredColorScheme(appState.preferredColorScheme)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            AppMenuCommands()
        }

        // In-app SECURITY.md viewer. Reachable from Help → Security & Privacy
        // whitepaper. Bundle-loaded markdown rendered by a small hand-rolled
        // block parser; see SecurityDocView.
        Window("Security & Privacy", id: "security-doc") {
            SecurityDocView()
                .tint(appState.effectiveAccentColor)
                .preferredColorScheme(appState.preferredColorScheme)
        }
        .defaultSize(width: 760, height: 720)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(minWidth: 700, minHeight: 500)
        }
    }
}
