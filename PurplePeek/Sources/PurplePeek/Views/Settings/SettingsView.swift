import SwiftUI

/// Preferences window (⌘,). Tabs: General, Remote Server, Scan Roots, Backup.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView(store: appState.settingsStore)
                .tabItem { Label("General", systemImage: "gearshape") }
            RemoteServerSettingsView(store: appState.settingsStore)
                .tabItem { Label("Remote Server", systemImage: "server.rack") }
            ScanRootsSettingsView(store: appState.settingsStore)
                .tabItem { Label("Scan Roots", systemImage: "folder") }
            BackupSettingsView(store: appState.settingsStore)
                .tabItem { Label("Backup", systemImage: "archivebox") }
        }
        .frame(width: 540, height: 460)
    }
}
