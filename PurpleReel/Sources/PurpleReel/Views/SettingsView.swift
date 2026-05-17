import SwiftUI

struct SettingsView: View {
    @AppStorage("autoBackupEnabled") private var autoBackupEnabled: Bool = true
    @AppStorage("backupRetentionDays") private var backupRetentionDays: Int = 14

    var body: some View {
        TabView {
            Form {
                Section("Auto-backup") {
                    Toggle("Backup on launch", isOn: $autoBackupEnabled)
                    Stepper("Retention: \(backupRetentionDays) days",
                            value: $backupRetentionDays, in: 0...365)
                    Text("Backups land in ~/Downloads/PurpleReel backup/")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Backup", systemImage: "externaldrive") }

            VStack(alignment: .leading, spacing: 8) {
                Text("PurpleReel \(AppVersion.display)").font(.headline)
                Text("Media management for Final Cut Pro.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding()
    }
}
