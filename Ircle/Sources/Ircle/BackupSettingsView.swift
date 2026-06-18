import SwiftUI
import AppKit

/// Settings → Backup. Implements the PhantomLives auto-backup-on-launch UI
/// standard: enable toggle, directory picker + resolved path, retention
/// stepper, Run Now / Reveal, the recent-backups list with Test / Restore /
/// Reveal per row, last-backup readout, and a status line.
struct BackupSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var status: String = ""
    @State private var backups: [(url: URL, modified: Date, size: Int)] = []

    var body: some View {
        Form {
            Section("Automatic backup") {
                Toggle("Back up on launch", isOn: $settingsStore.settings.autoBackupEnabled)
                Stepper("Keep for \(retentionLabel)",
                        value: $settingsStore.settings.backupRetentionDays, in: 0...365)
            }

            Section("Location") {
                HStack {
                    Button("Choose…") { chooseDirectory() }
                    Button("Default") { settingsStore.settings.backupPath = "" }
                    Button("Reveal in Finder") { reveal(settingsStore.resolvedBackupPath) }
                }
                Text(settingsStore.resolvedBackupPath.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("Manual") {
                HStack {
                    Button("Run Backup Now") { runNow() }
                    Spacer()
                    Text(lastBackupReadout).foregroundStyle(.secondary).font(.caption)
                }
                if !status.isEmpty {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Recent backups") {
                if backups.isEmpty {
                    Text("No backups yet.").foregroundStyle(.secondary).font(.caption)
                } else {
                    ForEach(backups, id: \.url) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.url.lastPathComponent).font(.caption)
                                Text("\(Self.dateString(row.modified)) · \(Self.sizeString(row.size))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Test") { test(row.url) }
                            Button("Restore") { restore(row.url) }
                            Button("Reveal") { reveal(row.url) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
    }

    // MARK: - Actions

    private func runNow() {
        do {
            let url = try BackupService.doBackup(settingsStore: settingsStore)
            status = "Backed up to \(url.lastPathComponent)"
        } catch {
            status = "Backup failed: \(error.localizedDescription)"
        }
        refresh()
    }

    private func test(_ url: URL) {
        do {
            let r = try BackupService.verifyArchive(at: url)
            status = "✓ \(url.lastPathComponent): \(r.fileCount) files, \(r.serverCount) server profile(s)."
        } catch {
            status = "✗ \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func restore(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Restore this backup?"
        alert.informativeText = "This replaces your current Ircle settings with the contents of \(url.lastPathComponent). A safety backup is taken first."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try BackupService.restoreArchive(at: url,
                                             into: SettingsStore.supportDirectory,
                                             safetyBackupDir: settingsStore.resolvedBackupPath)
            status = "Restored \(url.lastPathComponent). Relaunch Ircle to load the restored settings."
        } catch {
            status = "Restore failed: \(error.localizedDescription)"
        }
        refresh()
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settingsStore.settings.backupPath = url.path
            refresh()
        }
    }

    private func reveal(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func refresh() {
        backups = BackupService.listBackups(in: settingsStore.resolvedBackupPath)
    }

    // MARK: - Formatting

    private var retentionLabel: String {
        let d = settingsStore.settings.backupRetentionDays
        return d == 0 ? "ever (no auto-delete)" : "\(d) day\(d == 1 ? "" : "s")"
    }

    private var lastBackupReadout: String {
        let s = settingsStore.settings.lastBackupAt
        return s.isEmpty ? "Never backed up" : "Last: \(s.replacingOccurrences(of: "T", with: " "))"
    }

    private static func dateString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: d)
    }

    private static func sizeString(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
