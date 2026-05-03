import SwiftUI

struct BackupSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    @State private var backups: [(url: URL, modified: Date, size: Int)] = []
    @State private var error: String?
    @State private var lastRunMessage: String?
    @State private var showingWipeAlert: Bool = false
    @State private var resetMessage: String?

    @State private var verifyResult: BackupService.VerifyResult?
    @State private var verifyError: String?
    @State private var pendingRestore: URL?
    @State private var restoreMessage: String?

    var body: some View {
        Form {
            Section("Backup") {
                Toggle("Enable auto-backup at launch", isOn: Binding(
                    get: { appState.settings.autoBackupEnabled },
                    set: { var s = appState.settings; s.autoBackupEnabled = $0; appState.settings = s }
                ))

                HStack {
                    TextField("(default: ~/Downloads/MasterClipper backup)", text: Binding(
                        get: { appState.settings.backupPath },
                        set: { var s = appState.settings; s.backupPath = $0; appState.settings = s }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseDir() }
                }

                Stepper("Retention: \(retentionLabel)", value: Binding(
                    get: { appState.settings.backupRetentionDays },
                    set: { var s = appState.settings; s.backupRetentionDays = $0; appState.settings = s }
                ), in: 0...365, step: 1)

                HStack {
                    Button("Run backup now") { runNow() }
                    if let msg = lastRunMessage {
                        Text(msg).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }

                Text("Resolved: \(appState.settingsStore.resolvedBackupPath.path)")
                    .font(.caption.monospaced()).foregroundStyle(.tertiary)
            }

            Section("Reset clip data") {
                Text("Deletes every row from clips, clip_postings, clip_categories, clip_history, calendar_events, prices, and id_sequences. Personas, sites, categories, and calendar rules are preserved. A backup is run first as a safety net.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(role: .destructive) {
                        showingWipeAlert = true
                    } label: {
                        Label("Backup & wipe all clip data", systemImage: "trash")
                    }
                    if let msg = resetMessage {
                        Text(msg).font(.caption).foregroundStyle(.green)
                    }
                }
            }

            Section("Recent backups") {
                if backups.isEmpty {
                    Text("No backups yet.").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(backups, id: \.url) { entry in
                        backupRow(entry)
                    }
                }
                HStack {
                    Button("Refresh list") { reload() }
                    if let msg = restoreMessage {
                        Text(msg).font(.caption).foregroundStyle(.green)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear { reload() }
        .alert("Wipe all clip data?", isPresented: $showingWipeAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Backup & wipe", role: .destructive) { wipeWithBackup() }
        } message: {
            Text("\(appState.clips.count) clip(s) and their associated postings, categories, calendar events, and history will be deleted. A backup of the current state will be written to the backup folder first. Personas, sites, categories, and calendar rules are kept.")
        }
        .alert(
            "Restore from \(pendingRestore?.lastPathComponent ?? "backup")?",
            isPresented: Binding(get: { pendingRestore != nil },
                                 set: { if !$0 { pendingRestore = nil } })
        ) {
            Button("Cancel", role: .cancel) { pendingRestore = nil }
            Button("Backup current & restore", role: .destructive) {
                if let url = pendingRestore { restore(from: url) }
                pendingRestore = nil
            }
        } message: {
            Text("This replaces the current database (\(appState.clips.count) clip(s) and all associated state) with the contents of the selected backup. A safety backup of the current state is written first.")
        }
        .sheet(item: Binding<VerifyBox?>(
            get: { verifyResult.map(VerifyBox.init) },
            set: { _ in verifyResult = nil }
        )) { box in
            VerifyResultSheet(result: box.value, restoreError: verifyError) {
                pendingRestore = box.value.archiveURL
                verifyResult = nil
            } onClose: {
                verifyResult = nil
            }
        }
    }

    // MARK: - Backup row

    private func backupRow(_ entry: (url: URL, modified: Date, size: Int)) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entry.url.lastPathComponent).font(.body.monospaced())
                Text("\(entry.modified.formatted(date: .abbreviated, time: .standard)) · \(format(bytes: entry.size))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Test") { test(url: entry.url) }
                .help("Extract to a temp dir and check the database is valid. Non-destructive.")
            Button("Restore") { pendingRestore = entry.url }
                .help("Replace the current database with this backup. A safety backup of the current state will run first.")
            Button("Reveal") {
                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            }
        }
    }

    private func wipeWithBackup() {
        do {
            let backupURL = try BackupService.doBackup(settingsStore: appState.settingsStore)
            try DatabaseService.shared.wipeAllClipData()
            appState.reloadAll()
            resetMessage = "Wiped. Pre-wipe backup: \(backupURL.lastPathComponent)"
            error = nil
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Test / Restore

    private func test(url: URL) {
        do {
            verifyError = nil
            verifyResult = try BackupService.verifyArchive(at: url)
        } catch {
            verifyError = error.localizedDescription
            // Show the sheet anyway with the error message so the user sees why
            verifyResult = BackupService.VerifyResult(
                archiveURL: url, archiveSize: 0, fileCount: 0, totalBytes: 0,
                migrations: [], clipCount: 0, personaCount: 0, siteCount: 0,
                postingCount: 0, categoryCount: 0, calendarEventCount: 0,
                entries: []
            )
        }
    }

    private func restore(from url: URL) {
        do {
            // Safety backup of current state
            let safetyURL = try BackupService.doBackup(settingsStore: appState.settingsStore)

            // Replace files
            let supportDir = DatabaseService.supportDirectory
            try BackupService.restoreArchive(at: url, into: supportDir)

            // Re-open the GRDB pool against the now-on-disk DB and reload UI
            try DatabaseService.shared.reopenDatabase()
            appState.settingsStore.load()
            appState.reloadAll()

            restoreMessage = "Restored from \(url.lastPathComponent). Pre-restore backup: \(safetyURL.lastPathComponent)"
            error = nil
            reload()
        } catch {
            self.error = "Restore failed: \(error.localizedDescription)"
        }
    }

    private var retentionLabel: String {
        let d = appState.settings.backupRetentionDays
        return d == 0 ? "keep forever" : "\(d) day\(d == 1 ? "" : "s")"
    }

    private func chooseDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            var s = appState.settings
            s.backupPath = url.path
            appState.settings = s
            reload()
        }
    }

    private func runNow() {
        do {
            let url = try BackupService.doBackup(settingsStore: appState.settingsStore)
            lastRunMessage = "Backup written to \(url.lastPathComponent)"
            error = nil
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reload() {
        backups = BackupService.listBackups(in: appState.settingsStore.resolvedBackupPath)
    }

    private func format(bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}

// MARK: - Verify result sheet

private struct VerifyBox: Identifiable {
    let value: BackupService.VerifyResult
    var id: URL { value.archiveURL }
}

private struct VerifyResultSheet: View {
    let result: BackupService.VerifyResult
    let restoreError: String?
    let onRestore: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if restoreError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.title)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green).font(.title)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.archiveURL.lastPathComponent)
                        .font(.headline.monospaced())
                    if let err = restoreError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    } else {
                        Text("Backup looks valid.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if restoreError == nil {
                Form {
                    Section("Contents") {
                        LabeledContent("Files", value: "\(result.fileCount)")
                        LabeledContent("Total bytes", value: format(bytes: result.totalBytes))
                        LabeledContent("Archive size", value: format(bytes: Int64(result.archiveSize)))
                    }
                    Section("Database") {
                        LabeledContent("Migrations", value: result.migrations.joined(separator: ", "))
                        LabeledContent("Clips",      value: "\(result.clipCount)")
                        LabeledContent("Postings",   value: "\(result.postingCount)")
                        LabeledContent("Categories", value: "\(result.categoryCount)")
                        LabeledContent("Personas",   value: "\(result.personaCount)")
                        LabeledContent("Sites",      value: "\(result.siteCount)")
                        LabeledContent("Calendar events", value: "\(result.calendarEventCount)")
                    }
                    Section("Entries (sample)") {
                        ForEach(result.entries, id: \.self) { e in
                            Text(e).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
                .formStyle(.grouped)
            }

            HStack {
                Spacer()
                if restoreError == nil {
                    Button("Restore from this backup", role: .destructive, action: onRestore)
                        .buttonStyle(.borderedProminent)
                }
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 460)
    }

    private func format(bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}
