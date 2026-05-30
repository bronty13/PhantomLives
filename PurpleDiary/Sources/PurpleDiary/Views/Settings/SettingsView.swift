import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }

            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }

            LockSettingsTab()
                .tabItem { Label("Lock", systemImage: "lock.fill") }

            BackupSettingsTab()
                .tabItem { Label("Backup", systemImage: "externaldrive.fill.badge.timemachine") }
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 500)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var confirmRestoreSamples = false
    @State private var restoreMessage: String?

    var body: some View {
        Form {
            Section("Writing") {
                Stepper("Daily word goal: \(goalLabel)", value: Binding(
                    get: { appState.settings.dailyWordGoal },
                    set: { var s = appState.settings; s.dailyWordGoal = $0; appState.settings = s }
                ), in: 0...5000, step: 50)
                Toggle("Week starts on Monday", isOn: Binding(
                    get: { appState.settings.weekStartsMonday },
                    set: { var s = appState.settings; s.weekStartsMonday = $0; appState.settings = s }
                ))
            }
            Section("Sample data") {
                Text("PurpleDiary seeds a few sample entries on first launch so the app isn't empty. Click below to add them again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    confirmRestoreSamples = true
                } label: {
                    Label("Restore Sample Entries…", systemImage: "arrow.clockwise.circle")
                }
            }
            Section("About") {
                LabeledContent("Version", value: AppVersion.display)
                LabeledContent("Database", value: DatabaseService.shared.databaseURL.path)
            }
        }
        .formStyle(.grouped)
        .alert("Restore sample entries?", isPresented: $confirmRestoreSamples) {
            Button("Cancel", role: .cancel) {}
            Button("Restore") {
                let added = SampleDataService.restoreSamples()
                appState.reloadAll()
                restoreMessage = added ? "Sample entries added." : "Nothing was added."
            }
        } message: {
            Text("Adds the sample entries to your journal. Your existing entries are untouched.")
        }
        .alert("Done", isPresented: Binding(
            get: { restoreMessage != nil },
            set: { if !$0 { restoreMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    private var goalLabel: String {
        let g = appState.settings.dailyWordGoal
        return g == 0 ? "off" : "\(g) words"
    }
}

// MARK: - Appearance

struct AppearanceSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Color scheme", selection: Binding(
                    get: { appState.settings.colorScheme },
                    set: { var s = appState.settings; s.colorScheme = $0; appState.settings = s }
                )) {
                    Text("Match system").tag("auto")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }
            Section("Accent") {
                ColorPicker("Accent color", selection: Binding(
                    get: { Color(hex: appState.settings.accentColorHex) ?? .purple },
                    set: { newVal in
                        var s = appState.settings
                        s.accentColorHex = newVal.toHex() ?? s.accentColorHex
                        appState.settings = s
                    }
                ), supportsOpacity: false)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Lock

struct LockSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("App lock") {
                Toggle("Require a passcode to open PurpleDiary", isOn: Binding(
                    get: { appState.settings.lockEnabled },
                    set: { var s = appState.settings; s.lockEnabled = $0; appState.settings = s }
                ))
                Toggle("Lock on launch", isOn: Binding(
                    get: { appState.settings.lockOnLaunch },
                    set: { var s = appState.settings; s.lockOnLaunch = $0; appState.settings = s }
                ))
                .disabled(!appState.settings.lockEnabled)
                Toggle("Allow Touch ID", isOn: Binding(
                    get: { appState.settings.requireBiometrics },
                    set: { var s = appState.settings; s.requireBiometrics = $0; appState.settings = s }
                ))
                .disabled(!appState.settings.lockEnabled)
            }
            Section {
                Text("Phase 1 scaffold: the lock toggles persist, but the lock screen and passphrase/Keychain wiring land in the next milestone. Encryption-at-rest (SQLCipher) is tracked in SCOPING.md → Phase 1.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Backup

struct BackupSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    @State private var backups: [(url: URL, modified: Date, size: Int)] = []
    @State private var error: String?
    @State private var lastRunMessage: String?
    @State private var pendingRestore: URL?
    @State private var restoreMessage: String?
    @State private var verifyMessage: String?

    var body: some View {
        Form {
            Section("Auto-backup") {
                Toggle("Run backup at every launch", isOn: Binding(
                    get: { appState.settings.autoBackupEnabled },
                    set: { var s = appState.settings; s.autoBackupEnabled = $0; appState.settings = s }
                ))
                HStack {
                    TextField("(default: ~/Downloads/PurpleDiary backup)", text: Binding(
                        get: { appState.settings.backupPath },
                        set: { var s = appState.settings; s.backupPath = $0; appState.settings = s }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseDir() }
                    Button("Default") {
                        var s = appState.settings; s.backupPath = ""; appState.settings = s; reload()
                    }
                }
                Stepper("Retention: \(retentionLabel)", value: Binding(
                    get: { appState.settings.backupRetentionDays },
                    set: { var s = appState.settings; s.backupRetentionDays = $0; appState.settings = s }
                ), in: 0...365, step: 1)
                HStack {
                    Button("Run Backup Now") { runNow() }
                    if let msg = lastRunMessage {
                        Text(msg).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([appState.settingsStore.resolvedBackupPath])
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }
                Text("Resolved: \(appState.settingsStore.resolvedBackupPath.path)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                if !appState.settings.lastBackupAt.isEmpty {
                    Text("Last backup: \(appState.settings.lastBackupAt)")
                        .font(.caption).foregroundStyle(.secondary)
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
                    if let msg = verifyMessage { Text(msg).font(.caption).foregroundStyle(.secondary) }
                    if let msg = restoreMessage { Text(msg).font(.caption).foregroundStyle(.green) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { reload() }
        .alert(
            "Restore from \(pendingRestore?.lastPathComponent ?? "backup")?",
            isPresented: Binding(get: { pendingRestore != nil },
                                 set: { if !$0 { pendingRestore = nil } })
        ) {
            Button("Cancel", role: .cancel) { pendingRestore = nil }
            Button("Back up current & restore", role: .destructive) {
                if let url = pendingRestore { restore(from: url) }
                pendingRestore = nil
            }
        } message: {
            Text("Replaces the current journal with the contents of the selected backup. A safety backup of the current state is written first.")
        }
    }

    private func backupRow(_ entry: (url: URL, modified: Date, size: Int)) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(entry.url.lastPathComponent).font(.body.monospaced())
                Text("\(entry.modified.formatted(date: .abbreviated, time: .standard)) · \(format(bytes: entry.size))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Test") { test(url: entry.url) }
            Button("Restore") { pendingRestore = entry.url }
            Button("Reveal") {
                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
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
            lastRunMessage = "Wrote \(url.lastPathComponent)"
            error = nil
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func test(url: URL) {
        do {
            let r = try BackupService.verifyArchive(at: url)
            verifyMessage = "✓ \(r.entryCount) entries, \(r.tagCount) tags"
        } catch {
            verifyMessage = "✗ \(error.localizedDescription)"
        }
    }

    private func restore(from url: URL) {
        do {
            let safety = try BackupService.doBackup(settingsStore: appState.settingsStore)
            try BackupService.restoreArchive(at: url, into: DatabaseService.supportDirectory)
            try DatabaseService.shared.reopenDatabase()
            appState.settingsStore.load()
            appState.reloadAll()
            restoreMessage = "Restored. Safety backup: \(safety.lastPathComponent)"
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
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}
