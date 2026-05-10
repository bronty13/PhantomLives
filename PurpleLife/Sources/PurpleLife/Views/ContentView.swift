import SwiftUI

/// Phase 1 placeholder. The real screens (Today, Sidebar, TableView, …)
/// are implemented in Phase 2 from `~/Downloads/PurpleLife-handoff.zip`.
/// For now this view exists so the app launches, the backup-on-launch
/// fires, and the round-trip test has something to drive.
struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("PurpleLife")
                .font(.largeTitle).bold()
            Text("Phase 1 scaffold — \(AppVersion.display)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 8)

            HStack(spacing: 24) {
                LabeledStat(label: "Objects", value: "\(appState.objectCount)")
                LabeledStat(label: "Last backup", value: lastBackupDisplay)
            }

            HStack {
                Button("Refresh") { appState.reloadAll() }
                Button("Run backup now") {
                    do {
                        let url = try BackupService.doBackup(settingsStore: appState.settingsStore)
                        NSLog("PurpleLife: manual backup wrote \(url.lastPathComponent)")
                    } catch {
                        NSLog("PurpleLife: manual backup failed — \(error.localizedDescription)")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var lastBackupDisplay: String {
        let raw = appState.settingsStore.settings.lastBackupAt
        return raw.isEmpty ? "—" : raw
    }
}

private struct LabeledStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.title2)
                .monospacedDigit()
        }
    }
}
