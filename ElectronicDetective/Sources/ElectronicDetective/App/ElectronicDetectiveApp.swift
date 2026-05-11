import SwiftUI

@main
struct ElectronicDetectiveApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var assets   = AssetResolver.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(appState.settings)
                .environmentObject(assets)
                .frame(minWidth: 1100, minHeight: 760)
        }
        .defaultSize(width: 1300, height: 860)
        .windowToolbarStyle(.unified(showsTitle: true))

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(appState.settings)
                .environmentObject(assets)
                .frame(minWidth: 540, minHeight: 480)
        }
    }
}
