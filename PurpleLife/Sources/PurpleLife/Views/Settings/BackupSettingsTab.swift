import SwiftUI
import AppKit

/// PhantomLives convention surface for backup. Wired to the `BackupService`
/// primitives that Phase 1 already ships. Mirrors Timeliner's pane so
/// muscle memory carries between apps in the family.
struct BackupSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    @State private var backups: [(url: URL, modified: Date, size: Int)] = []
    @State private var error: String?
    @State private var lastRunMessage: String?
    @State private var pendingRestore: URL?
    @State private var restoreMessage: String?

    /// Per-row test state. The "Last test result" section used to be
    /// the only feedback for the Test button, but it landed below the
    /// "Recent backups" list — when that list was long, the section
    /// rendered below the visible area and it looked like clicking
    /// Test did nothing. Per-row state shows the result inline next to
    /// the button that triggered it.
    @State private var testingURL: URL?
    @State private var testResults: [URL: BackupService.VerifyResult] = [:]
    @State private var testErrors: [URL: String] = [:]

    // Plaintext snapshot (Tier 5).
    @State private var showingSnapshotSheet = false
    @State private var snapshotFormat: PlaintextSnapshotService.Format = .zipWithSidecars
    @State private var snapshotIncludeVault: Bool = false
    @State private var snapshotRunning = false
    @State private var snapshotMessage: String?
    @State private var snapshotError: String?

    var body: some View {
        Form {
            Section("Auto-backup") {
                Toggle("Run backup at every launch", isOn: Binding(
                    get: { appState.settings.autoBackupEnabled },
                    set: { var s = appState.settings; s.autoBackupEnabled = $0; appState.settings = s }
                ))
                HStack {
                    TextField("(default: ~/Downloads/PurpleLife backup)", text: Binding(
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
                        .buttonStyle(.borderedProminent)
                    if let msg = lastRunMessage {
                        Text(msg).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }
                Text("Resolved: \(appState.settingsStore.resolvedBackupPath.path)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                if !appState.settings.lastBackupAt.isEmpty {
                    Text("Last backup: \(appState.settings.lastBackupAt)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Plaintext snapshot") {
                Text("Export your entire dataset, decrypted, to a single file you can store anywhere — encrypted thumb drive, 1Password attachment, paper printout for the most important records. The schema is bundled in the same file so a future reader can interpret every field.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Export plaintext snapshot…") { openSnapshotSheet() }
                        .disabled(snapshotRunning)
                    if snapshotRunning {
                        ProgressView().controlSize(.small)
                    }
                    if let msg = snapshotMessage {
                        Text(msg).font(.caption).foregroundStyle(.secondary)
                    }
                    if let err = snapshotError {
                        Text(err).font(.caption).foregroundStyle(.red)
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
            Text("Replaces the current database with the contents of the selected backup. A safety backup of the current state is written first.")
        }
        .sheet(isPresented: $showingSnapshotSheet) {
            snapshotSheet
        }
    }

    // MARK: - Plaintext snapshot sheet

    private var snapshotSheet: some View {
        let totalTypes = appState.schema.types.count
        let vaultTypeCount = appState.schema.vaultTypeIds.count
        let includedTypeCount = snapshotIncludeVault ? totalTypes : (totalTypes - vaultTypeCount)
        return VStack(alignment: .leading, spacing: 16) {
            Text("Export plaintext snapshot")
                .font(.title3.weight(.semibold))
            Text("Writes a single file with your decrypted data plus the schema needed to interpret it. The result is **plaintext on disk** — store somewhere safe.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("Format", selection: $snapshotFormat) {
                Text(PlaintextSnapshotService.Format.zipWithSidecars.menuLabel)
                    .tag(PlaintextSnapshotService.Format.zipWithSidecars)
                Text(PlaintextSnapshotService.Format.singleJSON.menuLabel)
                    .tag(PlaintextSnapshotService.Format.singleJSON)
            }
            .pickerStyle(.radioGroup)

            Group {
                if snapshotFormat == .zipWithSidecars {
                    Text("Bundles snapshot.json + attachments/<sha>.<ext> + README.txt inside a ZIP. Attachments stay binary-clean and openable per-file after unzip.")
                } else {
                    Text("Single self-contained JSON file with attachment bytes inlined as base64. Bigger on disk; portable into anything that can hold a long string.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Vault data")
                    .font(.headline)
                if vaultTypeCount == 0 {
                    Text("No Vault types — nothing extra to include.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if appState.vaultRevealed {
                    Toggle("Include Vault data (\(vaultTypeCount) type\(vaultTypeCount == 1 ? "" : "s"))",
                           isOn: $snapshotIncludeVault)
                    Text(snapshotIncludeVault
                         ? "Vault records will be written to the file in plaintext alongside everything else."
                         : "Vault types will be excluded; the rest of your data still exports.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("The Vault is locked. \(vaultTypeCount) Vault type\(vaultTypeCount == 1 ? "" : "s") will be excluded from the snapshot.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("To include Vault data, cancel here, choose **View → Show Vault…** (⇧⌘V), then run the export again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Text("Will export \(includedTypeCount) of \(totalTypes) type\(totalTypes == 1 ? "" : "s").")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { showingSnapshotSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Choose location & export…") { runSnapshot() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(snapshotRunning)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func openSnapshotSheet() {
        snapshotMessage = nil
        snapshotError = nil
        // Default to including Vault only if the Vault is actually
        // unlocked — otherwise we'd silently change the user's choice
        // in their absence. When locked, exclusion is forced.
        snapshotIncludeVault = appState.vaultRevealed
        showingSnapshotSheet = true
    }

    private func runSnapshot() {
        let format = snapshotFormat
        let excludingTypeIds: Set<String> = {
            // Locked Vault → always exclude. Unlocked Vault honors the
            // checkbox. This matches the Vault contract from the
            // 2026-05-14 design: Vault data never leaves the app
            // implicitly.
            if !appState.vaultRevealed { return appState.schema.vaultTypeIds }
            return snapshotIncludeVault ? [] : appState.schema.vaultTypeIds
        }()

        let panel = NSSavePanel()
        panel.title = "Export plaintext snapshot"
        panel.message = "The file written here will contain your data in plaintext. Pick a safe location."
        panel.nameFieldStringValue = PlaintextSnapshotService.defaultFilename(format: format)
        panel.directoryURL = appState.settingsStore.resolvedExportDirectory
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        showingSnapshotSheet = false
        snapshotRunning = true
        snapshotError = nil
        snapshotMessage = nil

        do {
            let result = try PlaintextSnapshotService.export(
                to: destination,
                format: format,
                schema: appState.schema,
                settings: appState.settings,
                excludingTypeIds: excludingTypeIds
            )
            snapshotMessage = "Wrote \(result.recordCount) record\(result.recordCount == 1 ? "" : "s"), \(result.attachmentCount) attachment\(result.attachmentCount == 1 ? "" : "s") → \(result.outputURL.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
        } catch {
            snapshotError = error.localizedDescription
        }
        snapshotRunning = false
    }

    private func backupRow(_ entry: (url: URL, modified: Date, size: Int)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading) {
                    Text(entry.url.lastPathComponent).font(.body.monospaced())
                    Text("\(entry.modified.formatted(date: .abbreviated, time: .standard)) · \(format(bytes: entry.size))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if testingURL == entry.url {
                    ProgressView().controlSize(.small)
                }
                Button("Test") { test(url: entry.url) }
                    .disabled(testingURL == entry.url)
                    .help("Extract to a temp dir and check the database is valid. Non-destructive.")
                Button("Restore") { pendingRestore = entry.url }
                    .disabled(testingURL == entry.url)
                    .help("Replace the current database with this backup. A safety backup of the current state will run first.")
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                }
            }
            if let result = testResults[entry.url] {
                let migrations = result.migrations.isEmpty
                    ? ""
                    : " · \(result.migrations.count) migration\(result.migrations.count == 1 ? "" : "s")"
                Label(
                    "Verified — \(result.objectCount) objects · \(result.fileCount) files · \(format(bytes: Int(result.totalBytes)))\(migrations)",
                    systemImage: "checkmark.seal.fill"
                )
                .font(.caption)
                .foregroundStyle(.green)
            } else if let err = testErrors[entry.url] {
                Label("Test failed: \(err)", systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
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

    private func test(url: URL) {
        // Verify can take noticeable time on large backups (zip extract +
        // sqlite open + count). Run on a background thread so the spinner
        // animates and the rest of the UI stays responsive. Result lands
        // back on the main actor via the explicit await hop.
        testErrors[url] = nil
        testResults[url] = nil
        testingURL = url
        Task.detached(priority: .userInitiated) {
            let outcome: Result<BackupService.VerifyResult, Error>
            do {
                let r = try BackupService.verifyArchive(at: url)
                outcome = .success(r)
            } catch {
                outcome = .failure(error)
            }
            await MainActor.run {
                switch outcome {
                case .success(let r):    testResults[url] = r
                case .failure(let err):  testErrors[url] = err.localizedDescription
                }
                if testingURL == url { testingURL = nil }
            }
        }
    }

    private func restore(from url: URL) {
        do {
            // Pre-restore safety backup is mandatory per PLAN.md § PhantomLives
            // conventions checklist. We capture the current state, then nuke
            // the support dir and unpack the chosen archive over it, then
            // reopen the GRDB pool against the swapped sqlite file.
            let safety = try BackupService.doBackup(settingsStore: appState.settingsStore)
            try BackupService.restoreArchive(at: url, into: DatabaseService.supportDirectory)
            try DatabaseService.shared.reopenDatabase()
            appState.settingsStore.load()
            appState.reloadAll()
            restoreMessage = "Restored. Pre-restore safety backup: \(safety.lastPathComponent)"
            error = nil
            reload()
        } catch {
            self.error = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func reload() {
        backups = BackupService.listBackups(in: appState.settingsStore.resolvedBackupPath)
    }

    private func format(bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }
}
