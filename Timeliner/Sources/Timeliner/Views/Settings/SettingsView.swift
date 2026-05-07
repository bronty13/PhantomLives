import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }

            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }

            ThemesSettingsTab()
                .tabItem { Label("Themes", systemImage: "swatchpalette.fill") }

            FontsSettingsTab()
                .tabItem { Label("Fonts", systemImage: "textformat") }

            TagsSettingsTab()
                .tabItem { Label("Tags", systemImage: "tag.fill") }

            PeopleRolesSettingsTab()
                .tabItem { Label("People Roles", systemImage: "person.2.fill") }

            NotificationsSettingsTab()
                .tabItem { Label("Notifications", systemImage: "bell.badge.fill") }

            ExportSettingsTab()
                .tabItem { Label("Export", systemImage: "square.and.arrow.up.fill") }

            BackupSettingsTab()
                .tabItem { Label("Backup", systemImage: "externaldrive.fill.badge.timemachine") }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 540)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Defaults") {
                Picker("Default case status", selection: Binding(
                    get: { appState.settings.defaultCaseStatus },
                    set: { var s = appState.settings; s.defaultCaseStatus = $0; appState.settings = s }
                )) {
                    ForEach(CaseStatus.allCases, id: \.self) {
                        Text($0.label).tag($0.rawValue)
                    }
                }

                Picker("Default importance", selection: Binding(
                    get: { appState.settings.defaultImportance },
                    set: { var s = appState.settings; s.defaultImportance = $0; appState.settings = s }
                )) {
                    ForEach(Importance.allCases, id: \.self) {
                        Text($0.label).tag($0.rawValue)
                    }
                }
            }
            Section("Calendar & dates") {
                Picker("Date format", selection: Binding(
                    get: { appState.settings.dateFormatStyle },
                    set: { var s = appState.settings; s.dateFormatStyle = $0; appState.settings = s }
                )) {
                    Text("Short").tag("short")
                    Text("Medium").tag("medium")
                    Text("Long").tag("long")
                    Text("Full").tag("full")
                }
                Toggle("Week starts on Monday", isOn: Binding(
                    get: { appState.settings.weekStartsMonday },
                    set: { var s = appState.settings; s.weekStartsMonday = $0; appState.settings = s }
                ))
            }
            Section("Search") {
                Toggle("Include notes in cross-case search", isOn: Binding(
                    get: { appState.settings.includeNotesInSearch },
                    set: { var s = appState.settings; s.includeNotesInSearch = $0; appState.settings = s }
                ))
            }
            Section("About") {
                LabeledContent("Version", value: AppVersion.display)
            }
        }
        .formStyle(.grouped)
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
                    get: { Color(hex: appState.settings.accentColorHex) ?? .accentColor },
                    set: { newVal in
                        var s = appState.settings
                        s.accentColorHex = newVal.toHex() ?? s.accentColorHex
                        appState.settings = s
                    }
                ), supportsOpacity: false)
                Slider(value: Binding(
                    get: { appState.settings.fontSize },
                    set: { var s = appState.settings; s.fontSize = $0; appState.settings = s }
                ), in: 11...18, step: 1) {
                    Text("Font size")
                } minimumValueLabel: { Text("11") } maximumValueLabel: { Text("18") }
                .frame(maxWidth: 360)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Themes

struct ThemesSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var builderDraft: UserTheme?
    @State private var builderIsExisting: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Pick a theme — or build your own.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("Built-in")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)],
                           spacing: 12) {
                    ForEach(Theme.all) { theme in
                        Button {
                            selectBuiltIn(theme)
                        } label: {
                            ThemePreviewCard(theme: theme,
                                              isSelected: appState.settings.themeName == theme.name)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Customize this theme…") {
                                openBuilder(basedOn: theme)
                            }
                        }
                    }
                }

                Divider().padding(.vertical, 4)

                HStack {
                    Text("Custom")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        openBuilder(basedOn: appState.currentTheme)
                    } label: {
                        Label("New custom theme", systemImage: "plus")
                    }
                }

                if appState.settings.userThemes.isEmpty {
                    Text("No custom themes yet — click **New custom theme** above or right-click a built-in to clone it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)],
                               spacing: 12) {
                        ForEach(appState.settings.userThemes) { ut in
                            let theme = ut.asTheme()
                            let activeKey = appState.settings.themeName
                            let selected =
                                activeKey == "user:\(ut.id.uuidString)" || activeKey == ut.name
                            Button {
                                selectUser(ut)
                            } label: {
                                ThemePreviewCard(theme: theme, isSelected: selected)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Edit…") { openBuilder(editing: ut) }
                                Button("Delete", role: .destructive) {
                                    deleteUserTheme(id: ut.id)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .sheet(item: $builderDraft) { draft in
            ThemeBuilderSheet(draft: draft, isExisting: builderIsExisting)
                .environmentObject(appState)
        }
    }

    private func selectBuiltIn(_ theme: Theme) {
        var s = appState.settings
        s.themeName = theme.name
        appState.settings = s
    }

    private func selectUser(_ ut: UserTheme) {
        var s = appState.settings
        s.themeName = "user:\(ut.id.uuidString)"
        appState.settings = s
    }

    private func openBuilder(basedOn base: Theme) {
        builderIsExisting = false
        builderDraft = UserTheme.newDraft(
            basedOn: base,
            name: "\(base.name) — custom"
        )
    }

    private func openBuilder(editing ut: UserTheme) {
        builderIsExisting = true
        builderDraft = ut
    }

    private func deleteUserTheme(id: UUID) {
        var s = appState.settings
        s.userThemes.removeAll { $0.id == id }
        if s.themeName == "user:\(id.uuidString)" {
            s.themeName = "Default"
        }
        appState.settings = s
    }
}

// MARK: - Tags

struct TagsSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TagsView()
            .navigationTitle("Tags")
    }
}

// MARK: - People Roles

struct PeopleRolesSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Role colors") {
                Text("These colors appear on person chips throughout the app and in HTML exports.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(PersonRole.allCases, id: \.self) { role in
                    HStack {
                        Image(systemName: role.systemImage)
                            .frame(width: 22)
                        Text(role.label)
                        Spacer()
                        ColorPicker("", selection: Binding(
                            get: { Color(hex: appState.settingsStore.roleColorHex(for: role)) ?? .gray },
                            set: { new in
                                let hex = new.toHex() ?? role.defaultColorHex
                                appState.settingsStore.setRoleColor(hex, for: role)
                            }
                        ), supportsOpacity: false)
                        .labelsHidden()
                        Button("Reset") {
                            appState.settingsStore.setRoleColor(role.defaultColorHex, for: role)
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Export

struct ExportSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Export directory") {
                HStack {
                    TextField("(default: ~/Downloads/Timeliner)", text: Binding(
                        get: { appState.settings.defaultExportDirectory },
                        set: { var s = appState.settings; s.defaultExportDirectory = $0; appState.settings = s }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseDir() }
                }
                Text("Resolved: \(appState.settingsStore.resolvedExportDirectory.path)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Section("Export this case") {
                if let aCase = appState.selectedCase {
                    HStack {
                        Text("Selected: \(aCase.title.isEmpty ? "Untitled case" : aCase.title)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Export to HTML now") { export(aCase: aCase) }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    Text("Select a case in the sidebar first.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            var s = appState.settings
            s.defaultExportDirectory = url.path
            appState.settings = s
        }
    }

    private func export(aCase: Case) {
        do {
            let url = try ExportService.exportCaseAsHTML(
                aCase,
                events: appState.events.filter { $0.caseId == aCase.id },
                people: appState.people.filter { $0.caseId == aCase.id },
                tagsByEvent: appState.tagsByEvent,
                peopleByEvent: appState.peopleByEvent,
                exportDir: appState.settingsStore.resolvedExportDirectory
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSLog("Timeliner: export failed — \(error.localizedDescription)")
        }
    }
}

// MARK: - Backup

struct BackupSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    @State private var backups: [(url: URL, modified: Date, size: Int)] = []
    @State private var error: String?
    @State private var lastRunMessage: String?
    @State private var verifyResult: BackupService.VerifyResult?
    @State private var verifyError: String?
    @State private var pendingRestore: URL?
    @State private var restoreMessage: String?

    var body: some View {
        Form {
            Section("Auto-backup") {
                Toggle("Run backup at every launch", isOn: Binding(
                    get: { appState.settings.autoBackupEnabled },
                    set: { var s = appState.settings; s.autoBackupEnabled = $0; appState.settings = s }
                ))
                HStack {
                    TextField("(default: ~/Downloads/Timeliner backup)", text: Binding(
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
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                if !appState.settings.lastBackupAt.isEmpty {
                    Text("Last backup: \(appState.settings.lastBackupAt)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Attachments in DB",
                                value: attachmentBytesReadout)
                    .help("BLOB attachments are stored in the SQLite database, so they're included in every backup zip. Big files mean big backups.")
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
                .help("Extract to a temp dir and check the database is valid. Non-destructive.")
            Button("Restore") { pendingRestore = entry.url }
                .help("Replace the current database with this backup. A safety backup of the current state will run first.")
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
            lastRunMessage = "Backup written to \(url.lastPathComponent)"
            error = nil
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func test(url: URL) {
        do {
            verifyError = nil
            verifyResult = try BackupService.verifyArchive(at: url)
        } catch {
            verifyError = error.localizedDescription
        }
    }

    private func restore(from url: URL) {
        do {
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
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }

    private var attachmentBytesReadout: String {
        let bytes = (try? DatabaseService.shared.attachmentTotalBytes()) ?? 0
        let kb = Double(bytes) / 1024
        if bytes == 0 { return "—" }
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}
