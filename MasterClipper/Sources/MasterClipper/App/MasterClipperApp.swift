import SwiftUI

@main
struct MasterClipperApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1100, minHeight: 700)
                .tint(appState.effectiveAccentColor)
                .preferredColorScheme(appState.preferredColorScheme)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            AppMenuCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 520)
        }
    }
}
