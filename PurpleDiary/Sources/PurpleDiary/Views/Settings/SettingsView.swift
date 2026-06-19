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

            RemindersSettingsTab()
                .tabItem { Label("Reminders", systemImage: "bell") }

            SecuritySettingsTab()
                .tabItem { Label("Security", systemImage: "lock.fill") }

            BackupSettingsTab()
                .tabItem { Label("Backup", systemImage: "externaldrive.fill.badge.timemachine") }
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 500)
    }
}

// MARK: - Reminders

struct RemindersSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Daily reminder") {
                Toggle("Remind me to journal each day", isOn: Binding(
                    get: { appState.settings.reminderEnabled },
                    set: { on in
                        var s = appState.settings; s.reminderEnabled = on; appState.settings = s
                        if on {
                            Task {
                                _ = await NotificationService.requestAuthorization()
                                appState.updateReminderSchedule()
                            }
                        } else {
                            appState.updateReminderSchedule()
                        }
                    }
                ))
                DatePicker("Time", selection: Binding(
                    get: {
                        var c = DateComponents()
                        c.hour = appState.settings.reminderHour
                        c.minute = appState.settings.reminderMinute
                        return Calendar.current.date(from: c) ?? Date()
                    },
                    set: { date in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                        var s = appState.settings
                        s.reminderHour = c.hour ?? 20
                        s.reminderMinute = c.minute ?? 0
                        appState.settings = s
                        appState.updateReminderSchedule()
                    }
                ), displayedComponents: .hourAndMinute)
                .disabled(!appState.settings.reminderEnabled)
            }
            Section {
                Text("A gentle local notification — nothing leaves your Mac. If macOS asks, allow notifications for PurpleDiary so the reminder can appear. You can fine-tune or silence it any time in System Settings → Notifications.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var confirmRestoreSamples = false
    @State private var confirmPopulate = false
    @State private var confirmRemoveSamples = false
    @State private var resultMessage: String?
    @State private var showingExport = false

    private var sampleCount: Int { appState.settings.sampleDataIds.count }

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
                Text("PurpleDiary seeds a few sample entries on first launch. You can add the originals back, bulk-add 100 varied entries to try the timeline / calendar / search at scale, or remove everything the app generated.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    confirmRestoreSamples = true
                } label: {
                    Label("Restore Sample Entries…", systemImage: "arrow.clockwise.circle")
                }
                Button {
                    confirmPopulate = true
                } label: {
                    Label("Add 100 Sample Entries…", systemImage: "square.stack.3d.up")
                }
                Button(role: .destructive) {
                    confirmRemoveSamples = true
                } label: {
                    Label("Remove All Sample Entries (\(sampleCount))…", systemImage: "trash")
                }
                .disabled(sampleCount == 0)
            }
            Section("Export") {
                Text("Save your whole journal as Markdown, HTML, PDF, or JSON. Files are written to the folder below; nothing leaves your Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("(default: ~/Downloads/PurpleDiary)", text: Binding(
                        get: { appState.settings.defaultExportDirectory },
                        set: { var s = appState.settings; s.defaultExportDirectory = $0; appState.settings = s }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseExportDir() }
                    Button("Default") {
                        var s = appState.settings; s.defaultExportDirectory = ""; appState.settings = s
                    }
                }
                Text("Resolved: \(appState.settingsStore.resolvedExportDirectory.path)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                HStack {
                    Button {
                        showingExport = true
                    } label: {
                        Label("Export Journal…", systemImage: "square.and.arrow.up")
                    }
                    Spacer()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([appState.settingsStore.resolvedExportDirectory])
                    }
                }
            }
            Section("About") {
                LabeledContent("Version", value: AppVersion.display)
                LabeledContent("Database", value: DatabaseService.shared.databaseURL.path)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingExport) {
            ExportSheet().environmentObject(appState)
        }
        .alert("Restore sample entries?", isPresented: $confirmRestoreSamples) {
            Button("Cancel", role: .cancel) {}
            Button("Restore") {
                let added = SampleDataService.restoreSamples(settingsStore: appState.settingsStore)
                appState.reloadAll()
                resultMessage = added ? "Sample entries added." : "Nothing was added."
            }
        } message: {
            Text("Adds the four original sample entries. Your existing entries are untouched.")
        }
        .alert("Add 100 sample entries?", isPresented: $confirmPopulate) {
            Button("Cancel", role: .cancel) {}
            Button("Add 100") {
                let n = SampleDataService.populate(count: 100, settingsStore: appState.settingsStore)
                appState.reloadAll()
                resultMessage = "Added \(n) sample entries spread across the last few months."
            }
        } message: {
            Text("Generates 100 varied entries over the past ~120 days. Useful for trying things at scale; remove them anytime.")
        }
        .alert("Remove all sample entries?", isPresented: $confirmRemoveSamples) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                let n = SampleDataService.removeAllSamples(settingsStore: appState.settingsStore)
                appState.reloadAll()
                resultMessage = "Removed \(n) sample entries. Your own entries are untouched."
            }
        } message: {
            Text("Deletes only the \(sampleCount) entries PurpleDiary generated as samples. Entries you wrote yourself are never touched.")
        }
        .alert("Done", isPresented: Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private var goalLabel: String {
        let g = appState.settings.dailyWordGoal
        return g == 0 ? "off" : "\(g) words"
    }

    private func chooseExportDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            var s = appState.settings
            s.defaultExportDirectory = url.path
            appState.settings = s
        }
    }
}

// MARK: - Appearance

struct AppearanceSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    // Three-column grid of theme cards; adapts down on a narrow window.
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]

    private var selectedThemeId: String? { appState.selectedTheme?.id }

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Theme.all) { theme in
                        ThemeSwatch(theme: theme, isSelected: theme.id == selectedThemeId) {
                            appState.applyTheme(theme)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Theme")
            } footer: {
                Text(selectedThemeId == nil
                     ? "Custom — a hand-picked accent or “Match system” mode. Pick a theme above to switch, or fine-tune below."
                     : "Selected: \(appState.selectedTheme?.name ?? ""). Each theme sets an accent color and a light or dark look across the whole app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Custom") {
                Picker("Mode", selection: Binding(
                    get: { appState.settings.colorScheme },
                    set: { var s = appState.settings; s.colorScheme = $0; appState.settings = s }
                )) {
                    Text("Match system").tag("auto")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

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

/// A tappable theme preview card: the theme's representative background with a
/// pair of accent chips and its name, ringed + check-marked when it's the one in
/// effect. Previews are static (they don't change the live window); tapping
/// applies the theme via `AppState.applyTheme`.
private struct ThemeSwatch: View {
    let theme: Theme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(theme.accent).frame(width: 22, height: 22)
                    Capsule().fill(theme.accent.opacity(0.45)).frame(width: 34, height: 10)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.accent)
                    }
                }
                Text(theme.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.previewForeground)
                Text(theme.isDark ? "Dark" : "Light")
                    .font(.caption2)
                    .foregroundStyle(theme.previewForeground.opacity(0.55))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.previewBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? theme.accent : Color.secondary.opacity(0.25),
                                  lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .help(theme.blurb)
    }
}

// MARK: - Security

struct SecuritySettingsTab: View {
    @EnvironmentObject private var appState: AppState

    @State private var passphraseSheet: PassphraseSheetMode?
    @State private var confirmRegenRecovery = false
    @State private var statusMessage: String?

    private var biometricsAvailable: Bool { BiometricAuthService.canAuthenticate(biometryOnly: false) }

    var body: some View {
        Form {
            Section("Encryption") {
                Label {
                    Text("Your journal is **encrypted at rest** (SQLCipher / AES-256). The key lives in this Mac's login Keychain.")
                } icon: {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.green)
                }
                .font(.callout)
            }

            Section("App lock") {
                Toggle("Require unlock to open PurpleDiary", isOn: Binding(
                    get: { appState.settings.lockEnabled },
                    set: { var s = appState.settings; s.lockEnabled = $0; appState.settings = s }
                ))
                Toggle("Lock on launch", isOn: Binding(
                    get: { appState.settings.lockOnLaunch },
                    set: { var s = appState.settings; s.lockOnLaunch = $0; appState.settings = s }
                ))
                .disabled(!appState.settings.lockEnabled)
                Toggle("Touch ID only (no password fallback)", isOn: Binding(
                    get: { appState.settings.biometryOnlyMode },
                    set: { var s = appState.settings; s.biometryOnlyMode = $0; appState.settings = s }
                ))
                .disabled(!appState.settings.lockEnabled || !biometricsAvailable)
                if !biometricsAvailable {
                    Text("Touch ID isn't available on this Mac, so password-only is used.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    appState.lockApp()
                } label: {
                    Label("Lock Now", systemImage: "lock.fill")
                }
                .disabled(!appState.settings.lockEnabled)
            }

            Section("Passphrase") {
                if appState.keyStore.hasPassphrase {
                    Text("A passphrase is set. It's required after locking and on the next launch.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button { passphraseSheet = .change } label: {
                        Label("Change Passphrase…", systemImage: "key")
                    }
                    Button(role: .destructive) { passphraseSheet = .remove } label: {
                        Label("Remove Passphrase…", systemImage: "key.slash")
                    }
                } else {
                    Text("Add a passphrase for an extra layer: even someone who can unlock this Mac's Keychain can't open your journal without it.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button { passphraseSheet = .set } label: {
                        Label("Set a Passphrase…", systemImage: "key")
                    }
                }
            }

            Section("Recovery key") {
                Text(appState.keyStore.hasRecoveryEnvelope
                     ? "A 24-word recovery key can unlock your journal if this Mac's Keychain entry is ever lost. Regenerate it if you think the old one was exposed."
                     : "No recovery key on file yet.")
                    .font(.callout).foregroundStyle(.secondary)
                Button { confirmRegenRecovery = true } label: {
                    Label("Regenerate Recovery Key…", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!appState.keyStore.isUnlocked)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $passphraseSheet) { mode in
            PassphraseSheet(mode: mode) { result in
                passphraseSheet = nil
                statusMessage = result
            }
            .environmentObject(appState)
        }
        .alert("Regenerate recovery key?", isPresented: $confirmRegenRecovery) {
            Button("Cancel", role: .cancel) {}
            Button("Regenerate") {
                if let words = try? appState.keyStore.regenerateRecoveryEnvelope() {
                    appState.pendingRecoveryKey = words
                }
            }
        } message: {
            Text("Creates a new 24-word recovery key and invalidates the old one. You'll be shown the new words to save.")
        }
        .alert("Done", isPresented: Binding(
            get: { statusMessage != nil },
            set: { if !$0 { statusMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(statusMessage ?? "")
        }
    }
}

enum PassphraseSheetMode: Identifiable {
    case set, change, remove
    var id: Int { hashValue }
}

/// Small modal for setting / changing / removing the passphrase.
struct PassphraseSheet: View {
    let mode: PassphraseSheetMode
    let onFinish: (String?) -> Void   // message on success, called with nil only if cancelled mid-flow

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var new1 = ""
    @State private var new2 = ""
    @State private var error: String?

    private var title: String {
        switch mode {
        case .set: return "Set a passphrase"
        case .change: return "Change passphrase"
        case .remove: return "Remove passphrase"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title3).bold()

            if mode == .change || mode == .remove {
                labeledSecure("Current passphrase", text: $current)
            }
            if mode == .set || mode == .change {
                labeledSecure(mode == .set ? "New passphrase" : "New passphrase", text: $new1)
                labeledSecure("Confirm new passphrase", text: $new2)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(mode == .remove ? "Remove" : "Save", role: mode == .remove ? .destructive : nil) {
                    apply()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canApply)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func labeledSecure(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            SecureField(label, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private var canApply: Bool {
        switch mode {
        case .set:    return !new1.isEmpty && new1 == new2
        case .change: return !current.isEmpty && !new1.isEmpty && new1 == new2
        case .remove: return !current.isEmpty
        }
    }

    private func apply() {
        do {
            switch mode {
            case .set:
                try appState.keyStore.addPassphrase(new1)
                onFinish("Passphrase set.")
            case .change:
                try appState.keyStore.changePassphrase(oldPassphrase: current, newPassphrase: new1)
                onFinish("Passphrase changed.")
            case .remove:
                try appState.keyStore.removePassphrase(currentPassphrase: current)
                onFinish("Passphrase removed.")
            }
            dismiss()
        } catch _ {
            self.error = (mode == .set) ? "Couldn't set the passphrase." : "That passphrase didn't match. Try again."
        }
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
