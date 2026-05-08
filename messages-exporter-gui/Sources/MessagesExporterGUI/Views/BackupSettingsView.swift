import SwiftUI
import AppKit

/// Settings → Backup section. Surfaces the auto-backup spec from
/// PhantomLives/CLAUDE.md: enable toggle, target directory, retention
/// stepper, "Run backup now" button, and a recent backups list with
/// Test (verify) / Restore (with safety pre-backup) / Reveal actions.
struct BackupSettingsView: View {
    @AppStorage(BackupService.BackupKeys.enabled)       private var enabled: Bool = true
    @AppStorage(BackupService.BackupKeys.path)          private var path: String  = ""
    @AppStorage(BackupService.BackupKeys.retentionDays) private var retentionDays: Int = BackupService.defaultRetentionDays
    @AppStorage(BackupService.BackupKeys.lastBackupAt)  private var lastBackupAt: String = ""

    @State private var backups: [(url: URL, modified: Date, size: Int)] = []
    @State private var statusMessage: String?
    @State private var verifyResult: BackupService.VerifyResult?
    @State private var pendingRestore: URL?
    @State private var running = false

    private var resolvedPath: String {
        path.isEmpty ? BackupService.defaultBackupDir.path : path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Auto-backup on launch", isOn: $enabled)
            HStack(alignment: .firstTextBaseline) {
                Text("Backup folder")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Choose…") { chooseFolder() }
                    .controlSize(.small)
                if !path.isEmpty {
                    Button("Reset") { path = "" }
                        .controlSize(.small)
                }
            }
            Text(resolvedPath)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)

            HStack {
                Stepper("Retention: \(retentionDaysLabel)",
                        value: $retentionDays, in: 0...365)
                    .frame(maxWidth: 320, alignment: .leading)
                Spacer()
            }
            Text("0 = keep forever. The trim only removes archives that match the `MessagesExporterGUI-` prefix — unrelated files in the folder are left alone.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Button(running ? "Working…" : "Run backup now") {
                    runBackupNow()
                }
                .disabled(running)
                .keyboardShortcut(.defaultAction)
                Spacer()
                Text(lastBackupCaption)
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Recent backups")
                .font(.callout).bold()
                .padding(.top, 4)

            if backups.isEmpty {
                Text("No backups in the folder yet. Hit Run backup now (or relaunch the app) to write the first one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(backups, id: \.url) { row in
                            backupRow(row)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(.vertical, 4)
        .onAppear { reloadList() }
        .sheet(item: Binding(
            get: { verifyResult.map { VerifyEnvelope(result: $0) } },
            set: { _ in verifyResult = nil }
        )) { envelope in
            VerifySheet(result: envelope.result) {
                verifyResult = nil
            }
        }
        .confirmationDialog(
            "Restore from this backup?",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRestore
        ) { url in
            Button("Restore", role: .destructive) {
                doRestore(url: url)
            }
            Button("Cancel", role: .cancel) { }
        } message: { _ in
            Text("This replaces the current run history and saved presets with the contents of the backup. A pre-restore safety backup will be written first.")
        }
    }

    @ViewBuilder
    private func backupRow(_ row: (url: URL, modified: Date, size: Int)) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.url.lastPathComponent)
                    .font(.system(.caption, design: .monospaced))
                Text("\(row.modified, style: .date) \(row.modified, style: .time) · \(BackupService.formatBytes(row.size))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Test") {
                verify(url: row.url)
            }
            .controlSize(.small)
            Button("Restore") {
                pendingRestore = row.url
            }
            .controlSize(.small)
            Button("Reveal") {
                NSWorkspace.shared.activateFileViewerSelecting([row.url])
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Actions

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: resolvedPath)
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
            reloadList()
        }
    }

    private func runBackupNow() {
        running = true
        Task { @MainActor in
            do {
                let url = try BackupService.doBackup()
                statusMessage = "Wrote \(url.lastPathComponent)"
            } catch {
                statusMessage = "Backup failed — \(error.localizedDescription)"
            }
            reloadList()
            running = false
        }
    }

    private func verify(url: URL) {
        Task { @MainActor in
            do {
                verifyResult = try BackupService.verifyArchive(at: url)
            } catch {
                statusMessage = "Verify failed — \(error.localizedDescription)"
            }
        }
    }

    private func doRestore(url: URL) {
        running = true
        Task { @MainActor in
            // Pre-restore safety backup.
            do {
                let safety = try BackupService.doBackup()
                statusMessage = "Pre-restore backup: \(safety.lastPathComponent)"
            } catch {
                statusMessage = "Pre-restore backup failed — \(error.localizedDescription) (continuing)"
            }
            do {
                try BackupService.restoreArchive(at: url)
                statusMessage = (statusMessage ?? "") + " · Restored from \(url.lastPathComponent). Relaunch the app for stores to reload."
            } catch {
                statusMessage = "Restore failed — \(error.localizedDescription)"
            }
            reloadList()
            running = false
        }
    }

    // MARK: - Helpers

    private func reloadList() {
        backups = BackupService.listBackups(in: URL(fileURLWithPath: resolvedPath))
    }

    private var retentionDaysLabel: String {
        retentionDays == 0 ? "keep forever" : "\(retentionDays) day\(retentionDays == 1 ? "" : "s")"
    }

    private var lastBackupCaption: String {
        if lastBackupAt.isEmpty { return "Never run." }
        guard let d = BackupService.parseISO(lastBackupAt) else { return "—" }
        return "Last backup: \(RelativeTime.short(d))"
    }
}

private struct VerifyEnvelope: Identifiable {
    var id: String { result.archiveURL.path }
    let result: BackupService.VerifyResult
}

private struct VerifySheet: View {
    let result: BackupService.VerifyResult
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2).foregroundStyle(.green)
                Text("Backup verified")
                    .font(.title3).bold()
            }
            VStack(alignment: .leading, spacing: 4) {
                row("Archive",       result.archiveURL.lastPathComponent)
                row("Archive size",  BackupService.formatBytes(result.archiveSize))
                row("Files inside",  "\(result.fileCount)")
                row("Total bytes",   BackupService.formatBytes(Int(result.totalBytes)))
                row("Run history",   "\(result.runHistoryCount) entries")
                row("Saved presets", "\(result.presetCount) entries")
            }
            .padding(10)
            .background(Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
        }
    }
}
