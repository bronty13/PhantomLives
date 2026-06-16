import SwiftUI

/// Preferences window (⌘,). Three tabs: General, Scan Roots, Backup.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView(store: appState.settingsStore)
                .tabItem { Label("General", systemImage: "gearshape") }
            ScanRootsSettingsView(store: appState.settingsStore)
                .tabItem { Label("Scan Roots", systemImage: "folder") }
            BackupSettingsView(store: appState.settingsStore)
                .tabItem { Label("Backup", systemImage: "archivebox") }
        }
        .frame(width: 540, height: 460)
    }
}
