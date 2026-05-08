import SwiftUI
import AppKit

struct BackupSettingsView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settingsStore: SettingsStore

    @State private var verifyResult: String?
    @State private var lastError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Toggle("Run automatic backup at every launch",
                       isOn: bind(\.autoBackupEnabled))
                HStack {
                    Text("Backup folder")
                    TextField("(default: ~/Downloads/PurpleTracker/Backup)", text: bind(\.backupPath))
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { pickDir() }
                }
                Text("Resolved: \(settingsStore.resolvedBackupPath.path)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)

                Stepper("Retention: \(settingsStore.settings.backupRetentionDays) day(s) (0 = keep forever)",
                        value: bind(\.backupRetentionDays), in: 0...3650)
                if !settingsStore.settings.lastBackupAt.isEmpty {
                    Text("Last backup: \(settingsStore.settings.lastBackupAt)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button {
                    do { _ = try app.runBackupNow() } catch { lastError = error.localizedDescription }
                } label: { Label("Run Backup Now", systemImage: "arrow.triangle.2.circlepath") }
                Spacer()
            }
            if let err = lastError {
                Text(err).foregroundStyle(.red).font(.caption)
            }
            if let v = verifyResult {
                Text(v).font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8).background(Color.secondary.opacity(0.10)).cornerRadius(6)
            }

            Divider()
            Text("Recent Backups").font(.headline)
            ScrollView {
                ForEach(BackupService.listBackups(in: settingsStore.resolvedBackupPath), id: \.url) { row in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(row.url.lastPathComponent).font(.system(.body, design: .monospaced))
                            Text("\(row.modified.formatted(date: .abbreviated, time: .shortened)) • \(ByteCountFormatter.string(fromByteCount: Int64(row.size), countStyle: .file))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Test")    { verify(row.url) }
                        Button("Restore") { restore(row.url) }
                        Button("Reveal")  {
                            NSWorkspace.shared.activateFileViewerSelecting([row.url])
                        }
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    private func pickDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            var s = settingsStore.settings
            s.backupPath = url.path
            settingsStore.settings = s
            settingsStore.save()
        }
    }

    private func verify(_ url: URL) {
        verifyResult = nil
        lastError = nil
        do {
            let r = try BackupService.verifyArchive(at: url)
            verifyResult = """
            ✓ Verified \(url.lastPathComponent)
            Size: \(ByteCountFormatter.string(fromByteCount: Int64(r.archiveSize), countStyle: .file))
            Files: \(r.fileCount)  •  Bytes: \(r.totalBytes)
            Migrations: \(r.migrations.joined(separator: ", "))
            Matters: \(r.matterCount)  •  Attachments: \(r.attachmentCount)  •  Time entries: \(r.timeEntryCount)
            """
        } catch {
            lastError = "Verify failed: \(error.localizedDescription)"
        }
    }

    private func restore(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Restore from \(url.lastPathComponent)?"
        alert.informativeText = "This will replace your current PurpleTracker data with the contents of this backup. A safety backup of the current data is taken first."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try app.restoreBackup(url) } catch { lastError = error.localizedDescription }
    }

    private func bind<T>(_ kp: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { settingsStore.settings[keyPath: kp] },
            set: { v in
                var s = settingsStore.settings
                s[keyPath: kp] = v
                settingsStore.settings = s
                settingsStore.save()
            }
        )
    }
}
