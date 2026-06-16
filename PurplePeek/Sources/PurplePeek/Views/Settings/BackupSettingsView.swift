import SwiftUI

/// Backup preferences (PhantomLives auto-backup-on-launch standard): toggle, destination,
/// retention, an on-demand backup, and a list of recent archives.
struct BackupSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: SettingsStore

    @State private var backups: [(url: URL, modified: Date, size: Int)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Back up on launch", isOn: $store.settings.autoBackupEnabled)

            LabeledContent("Location") {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(store.resolvedBackupPath.path)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    HStack {
                        Button("Change…") { chooseFolder() }
                        Button("Reveal") {
                            NSWorkspace.shared.activateFileViewerSelecting([store.resolvedBackupPath])
                        }
                    }
                }
            }

            Stepper("Keep backups for \(store.settings.backupRetentionDays) days",
                    value: $store.settings.backupRetentionDays, in: 1...365, step: 1)

            HStack {
                Button("Back Up Now") { appState.backupNow(); refresh() }
                Spacer()
            }

            Divider()
            Text("Recent backups").font(.headline)
            if backups.isEmpty {
                Text("No backups yet.").font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(backups, id: \.url) { b in
                            HStack {
                                Image(systemName: "archivebox.fill").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(b.url.lastPathComponent).font(.callout).lineLimit(1)
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(b.size), countStyle: .file))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([b.url]) }
                                    .buttonStyle(.link)
                            }
                            .padding(.vertical, 4)
                            Divider().opacity(0.2)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(20)
        .onAppear { refresh() }
    }

    private func refresh() { backups = appState.recentBackups() }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            store.settings.backupPath = url.path
            refresh()
        }
    }
}
