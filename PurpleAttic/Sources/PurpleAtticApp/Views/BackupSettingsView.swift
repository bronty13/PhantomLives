import SwiftUI
import AppKit
import PurpleAtticCore

/// Settings → Backup (PhantomLives ship-blocker). Backs up the app's config/state — NOT the
/// hundreds-of-GB photo archive, which has its own 3-copy strategy.
struct BackupSettingsView: View {
    @ObservedObject var store: SettingsStore
    @State private var backups: [(url: URL, modified: Date, size: Int)] = []
    @State private var statusLine: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Backup").font(.title3.weight(.semibold))
                Text("Automatically zips PurpleAttic's profiles + settings on launch. This protects your configuration, not the photo archive itself.")
                    .font(.callout).foregroundStyle(.secondary)

                Card(title: "Automatic backup") {
                    Toggle("Back up on launch", isOn: Binding(
                        get: { store.settings.autoBackupEnabled },
                        set: { store.settings.autoBackupEnabled = $0; store.save() }))
                    Stepper(value: Binding(
                        get: { store.settings.backupRetentionDays },
                        set: { store.settings.backupRetentionDays = $0; store.save() }),
                            in: 0...365, step: 1) {
                        Text(store.settings.backupRetentionDays == 0
                             ? "Retention: keep forever"
                             : "Retention: \(store.settings.backupRetentionDays) days")
                    }
                    PathField(label: "Backup folder",
                              path: Binding(
                                get: { store.settings.backupDirectoryOverride ?? store.resolvedBackupPath.path },
                                set: { store.settings.backupDirectoryOverride = $0; store.save() }))
                    HStack {
                        Button("Default") {
                            store.settings.backupDirectoryOverride = nil; store.save()
                        }
                        Spacer()
                        Button("Run Backup Now") { runBackupNow() }
                            .buttonStyle(.borderedProminent)
                    }
                    if !statusLine.isEmpty {
                        Text(statusLine).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Card(title: "Recent backups") {
                    if backups.isEmpty {
                        Text("No backups yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(backups, id: \.url) { b in
                            HStack {
                                Image(systemName: "doc.zipper")
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(b.url.lastPathComponent).font(.system(.caption, design: .monospaced))
                                    Text("\(format(date: b.modified)) · \(format(size: b.size))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Reveal") {
                                    NSWorkspace.shared.activateFileViewerSelecting([b.url])
                                }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .onAppear(perform: reload)
    }

    private func runBackupNow() {
        do {
            let url = try BackupService.doBackup(settingsStore: store)
            statusLine = "Wrote \(url.lastPathComponent)"
        } catch {
            statusLine = "Backup failed: \(error.localizedDescription)"
        }
        reload()
    }

    private func reload() {
        backups = BackupService.listBackups(in: store.resolvedBackupPath)
    }

    private func format(date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: date)
    }
    private func format(size: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
