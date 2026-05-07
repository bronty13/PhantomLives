import SwiftUI
import AppKit

@main
struct PurpleTrackerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(appState.settingsStore)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .defaultSize(width: 1400, height: 900)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Matter") {
                    if let firstType = appState.types.first {
                        _ = try? appState.createMatter(typeId: firstType.id)
                    }
                }
                .keyboardShortcut("n")
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(appState.settingsStore)
                .frame(minWidth: 760, minHeight: 540)
        }
    }
}
