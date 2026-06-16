import SwiftUI

@main
struct PurplePeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environment(\.appTheme, appState.currentTheme)
                .preferredColorScheme(appState.preferredColorScheme)
                .tint(appState.currentTheme.accentColor)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environment(\.appTheme, appState.currentTheme)
                .preferredColorScheme(appState.preferredColorScheme)
                .tint(appState.currentTheme.accentColor)
        }
    }
}
