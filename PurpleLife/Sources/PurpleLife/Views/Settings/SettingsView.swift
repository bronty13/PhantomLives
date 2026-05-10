import SwiftUI

/// Settings scene container. Phase 1 only has the Backup tab; Phase 2+
/// adds General / Appearance / etc. The TabView layout matches Timeliner
/// so users moving between PhantomLives apps see a uniform shape.
struct SettingsView: View {
    var body: some View {
        TabView {
            BackupSettingsTab()
                .tabItem { Label("Backup", systemImage: "externaldrive.fill.badge.timemachine") }
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}
