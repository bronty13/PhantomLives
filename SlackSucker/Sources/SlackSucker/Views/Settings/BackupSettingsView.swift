import SwiftUI
import AppKit

/// Settings → Backup pane. Implements the UI surface required by
/// PhantomLives/CLAUDE.md: toggle, path picker, retention stepper,
/// "Run backup now", recent-backups list with Test / Restore / Reveal.
struct BackupSettingsView: View {
    @AppStorage(BackupService.BackupKeys.enabled) private var enabled: Bool = true
    @AppStorage(BackupService.BackupKeys.path) private var pathRaw: String = ""
    @AppStorage(BackupService.BackupKeys.retentionDays) private var retentionDays: Int =
        BackupService.defaultRetentionDays
    @AppStorage(BackupService.BackupKeys.lastBackupAt) private var lastBackupAt: String = ""

    @State private var rows: [BackupListRow] = []
    @State private var runtimeError: String?
    @State private var verifyResult: BackupService.VerifyResult?
    @State private var restoreConfirm: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BACKUP")
                .font(AppFont.kicker())
                .foregroundStyle(.secondary)

            Toggle("Auto-backup on launch", isOn: $enabled)

            HStack {
                TextField("Default: ~/Downloads/SlackSucker backup", text: $pathRaw)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") { chooseDir() }
            }
            Text("Resolved: \(BackupService.resolvedBackupDir.path)")
                .font(AppFont.mono(10))
                .foregroundStyle(.tertiary)

            Stepper(value: $retentionDays, in: 0...365) {
                Text("Keep backups for \(retentionDays) day\(retentionDays == 1 ? "" : "s") (0 = forever)")
            }

            HStack(spacing: 8) {
                Button("Run backup now") {
                    do {
                        _ = try BackupService.doBackup()
                        runtimeError = nil
                        refreshList()
                    } catch {
                        runtimeError = error.localizedDescription
                    }
                }
                Button("Reveal folder") {
                    revealBackupFolder()
                }
                Button("Verify latest") {
                    if let latest = rows.first { test(latest.url) }
                }
                .disabled(rows.isEmpty)
                Button("Restore latest…") {
                    if let latest = rows.first { restoreConfirm = latest.url }
                }
                .disabled(rows.isEmpty)
                Spacer()
                if !lastBackupAt.isEmpty {
                    Text("Last: \(lastBackupAt)")
                        .font(AppFont.sans(11))
                        .foregroundStyle(.tertiary)
                }
            }

            if let runtimeError {
                Text(runtimeError)
                    .font(AppFont.sans(12))
                    .foregroundStyle(.red)
            }

            if rows.isEmpty {
                Text("No backups yet.")
                    .font(AppFont.sans(12))
                    .foregroundStyle(.tertiary)
            } else {
                Text("RECENT BACKUPS")
                    .font(AppFont.kicker())
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.url.lastPathComponent)
                                .font(AppFont.mono(11))
                            Text("\(BackupService.formatBytes(row.size)) · \(RelativeTime.short(row.modified))")
                                .font(AppFont.sans(11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Test") { test(row.url) }
                            .buttonStyle(.borderless)
                        Button("Restore") { restoreConfirm = row.url }
                            .buttonStyle(.borderless)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([row.url])
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .onAppear(perform: refreshList)
        .sheet(item: $verifyResult) { vr in
            VStack(alignment: .leading, spacing: 8) {
                Text("Backup contents")
                    .font(AppFont.display(15, weight: .semibold))
                Text("\(vr.fileCount) files · \(BackupService.formatBytes(Int(vr.totalBytes)))")
                Text("Runs: \(vr.runHistoryCount) · Presets: \(vr.presetCount)")
                ScrollView {
                    ForEach(vr.entries, id: \.self) { e in
                        Text(e)
                            .font(AppFont.mono(11))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxHeight: 240)
                Button("Close") { verifyResult = nil }
            }
            .padding(20)
            .frame(minWidth: 420)
        }
        .alert("Restore from this backup?", isPresented: Binding(
            get: { restoreConfirm != nil },
            set: { if !$0 { restoreConfirm = nil } }
        )) {
            Button("Restore", role: .destructive) {
                if let url = restoreConfirm { restore(url) }
                restoreConfirm = nil
            }
            Button("Cancel", role: .cancel) { restoreConfirm = nil }
        } message: {
            Text("This replaces SlackSucker's settings, run history, and presets with the contents of the selected backup. A safety backup is taken first.")
        }
    }

    // MARK: - Actions

    private func refreshList() {
        rows = BackupService.listBackups(in: BackupService.resolvedBackupDir).map {
            BackupListRow(url: $0.url, modified: $0.modified, size: $0.size)
        }
    }

    private func chooseDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = BackupService.resolvedBackupDir
        if panel.runModal() == .OK, let url = panel.url {
            pathRaw = url.path
        }
    }

    private func revealBackupFolder() {
        let dir = BackupService.resolvedBackupDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    private func test(_ url: URL) {
        do {
            verifyResult = try BackupService.verifyArchive(at: url)
        } catch {
            runtimeError = error.localizedDescription
        }
    }

    private func restore(_ url: URL) {
        do {
            // Belt-and-braces: take a safety backup of the current state
            // before clobbering it.
            _ = try BackupService.doBackup()
            try BackupService.restoreArchive(at: url)
            runtimeError = nil
            refreshList()
        } catch {
            runtimeError = error.localizedDescription
        }
    }
}

private struct BackupListRow: Identifiable {
    var id: URL { url }
    var url: URL
    var modified: Date
    var size: Int
}

extension BackupService.VerifyResult: Identifiable {
    public var id: URL { archiveURL }
}
