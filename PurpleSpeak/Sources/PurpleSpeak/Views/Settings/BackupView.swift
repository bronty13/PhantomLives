import SwiftUI
import AppKit

/// Settings → Backup. Implements the full PhantomLives backup UI checklist:
/// enable toggle, directory picker + Default, retention stepper, Run Now,
/// Reveal in Finder, last-backup status, and a recent-backups list with
/// per-row Test / Restore / Reveal.
struct BackupSettings: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var appState: AppState

    @State private var backups: [(url: URL, modified: Date, size: Int)] = []
    @State private var status: String?
    @State private var verifyText: String?

    var body: some View {
        Form {
            Section {
                Toggle("Back up automatically on launch", isOn: $settings.settings.autoBackupEnabled)
                LabeledContent("Backup folder") {
                    HStack {
                        Text(settings.settings.backupDirectory).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseDir() }
                        Button("Default") {
                            settings.settings.backupDirectory = "~/Downloads/PurpleSpeak backup"
                        }
                    }
                }
                Stepper("Keep backups for \(settings.settings.backupRetentionDays) day(s) (0 = forever)",
                        value: $settings.settings.backupRetentionDays, in: 0...365)
                HStack {
                    Button("Run Backup Now") { runNow() }
                    Button("Reveal in Finder") { revealDir() }
                    Spacer()
                    if let last = settings.settings.lastBackupAt {
                        Text("Last: \(last)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            }

            Section("Recent backups") {
                if backups.isEmpty {
                    Text("No backups yet.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(backups, id: \.url) { b in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(b.url.lastPathComponent).lineLimit(1)
                                Text("\(b.modified.formatted()) · \(ByteCountFormatter.string(fromByteCount: Int64(b.size), countStyle: .file))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Test") { test(b.url) }
                            Button("Restore") { restore(b.url) }
                            Button("Reveal") {
                                NSWorkspace.shared.activateFileViewerSelecting([b.url])
                            }
                        }
                    }
                }
                if let verifyText {
                    Text(verifyText).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        backups = BackupService.listBackups(in: settings.resolvedBackupPath)
    }

    private func runNow() {
        do {
            let url = try BackupService.doBackup(settingsStore: settings)
            status = "Wrote \(url.lastPathComponent)."
        } catch {
            status = "Backup failed: \(error.localizedDescription)"
        }
        refresh()
    }

    private func test(_ url: URL) {
        do {
            let r = try BackupService.verifyArchive(at: url)
            verifyText = "✓ \(r.archiveURL.lastPathComponent): \(r.fileCount) files, \(r.documentCount) documents."
        } catch {
            verifyText = "✗ \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func restore(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Restore from this backup?"
        alert.informativeText = "Your current library and settings will be replaced with the contents of \(url.lastPathComponent). A safety backup is taken first. Restart PurpleSpeak afterwards."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            _ = try? BackupService.doBackup(settingsStore: settings)   // safety net
            try BackupService.restoreArchive(at: url)
            verifyText = "Restored \(url.lastPathComponent). Restart PurpleSpeak to load it."
        } catch {
            verifyText = "Restore failed: \(error.localizedDescription)"
        }
        refresh()
    }

    private func chooseDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.settings.backupDirectory = url.path
            refresh()
        }
    }

    private func revealDir() {
        let dir = settings.resolvedBackupPath
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }
}
