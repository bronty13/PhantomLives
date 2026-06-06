import SwiftUI
import AppKit
import PurpleMarkRenderCore

/// The full preferences surface (the OpenMark settings set) plus PurpleMark's
/// default-handler, export-location, and backup controls.
struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            generalSection
            appearanceSection
            editorSection
            writingSection
            defaultAppSection
            updatesSection
            exportSection
            BackupSection(settings: settings)
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
    }

    // MARK: General

    private var generalSection: some View {
        Section("General") {
            Toggle("Zen mode", isOn: Binding(get: { settings.zenMode }, set: { settings.zenMode = $0 }))
            Text("Hide toolbar, sidebar, and status bar for distraction-free writing")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Word wrap", isOn: Binding(get: { settings.wordWrap }, set: { settings.wordWrap = $0 }))
            Toggle("Enable auto-save", isOn: Binding(get: { settings.autoSave }, set: { settings.autoSave = $0 }))
            Text("Automatically save changes as you type")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Theme").font(.subheadline)
                HStack(spacing: 10) {
                    ForEach(RenderTheme.allCases, id: \.self) { theme in
                        ThemeSwatch(theme: theme, selected: settings.theme == theme) {
                            settings.theme = theme
                        }
                    }
                }
            }
            Picker("Default view", selection: Binding(
                get: { settings.defaultView }, set: { settings.defaultView = $0 })) {
                Text("Document").tag(ViewMode.document)
                Text("Markdown").tag(ViewMode.markdown)
            }
            .pickerStyle(.segmented)
            Picker("Reading width", selection: Binding(
                get: { settings.readingWidth }, set: { settings.readingWidth = $0 })) {
                ForEach(ReadingWidth.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Editor contrast", isOn: Binding(
                get: { settings.editorContrast }, set: { settings.editorContrast = $0 }))
            Text("Use a distinct background for the markdown editor")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Editor

    private var editorSection: some View {
        Section("Editor") {
            HStack {
                Text("Font size")
                Slider(value: Binding(get: { settings.fontSize }, set: { settings.fontSize = $0 }),
                       in: 12...24, step: 1)
                Text("\(Int(settings.fontSize))pt").monospacedDigit().foregroundStyle(.secondary)
            }
            Picker("Editor font", selection: Binding(
                get: { settings.editorFontName }, set: { settings.editorFontName = $0 })) {
                Text("System Default").tag("System Default")
                Divider()
                ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            Text("Includes all installed fonts — choose accessibility fonts like OpenDyslexic here")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Show line numbers", isOn: Binding(
                get: { settings.showLineNumbers }, set: { settings.showLineNumbers = $0 }))
            Toggle("Sync scroll position between views", isOn: Binding(
                get: { settings.syncScroll }, set: { settings.syncScroll = $0 }))
            Toggle("Auto-close brackets and continue lists", isOn: Binding(
                get: { settings.autoCloseBrackets }, set: { settings.autoCloseBrackets = $0 }))
            Toggle("Check spelling while typing", isOn: Binding(
                get: { settings.checkSpelling }, set: { settings.checkSpelling = $0 }))
            Picker("Tab width", selection: Binding(
                get: { settings.tabWidth }, set: { settings.tabWidth = $0 })) {
                Text("2").tag(2); Text("4").tag(4); Text("8").tag(8)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Writing

    private var writingSection: some View {
        Section("Writing") {
            Toggle("Focus mode", isOn: Binding(get: { settings.focusMode }, set: { settings.focusMode = $0 }))
            Text("Dim text outside the current paragraph").font(.caption).foregroundStyle(.secondary)
            Toggle("Typewriter mode", isOn: Binding(get: { settings.typewriterMode }, set: { settings.typewriterMode = $0 }))
            Text("Keep the cursor line centered in the editor").font(.caption).foregroundStyle(.secondary)
            Toggle("Zen mode", isOn: Binding(get: { settings.zenMode }, set: { settings.zenMode = $0 }))
        }
    }

    // MARK: Default application

    @State private var isDefault = DefaultHandlerService.isDefault()

    private var defaultAppSection: some View {
        Section("Default Application") {
            HStack {
                Image(systemName: isDefault ? "checkmark.seal.fill" : "seal")
                    .foregroundStyle(isDefault ? .green : .secondary)
                Text(isDefault ? "PurpleMark is the default Markdown editor"
                               : "PurpleMark is not the default Markdown editor")
                Spacer()
                Button("Set as Default for .md") {
                    DefaultHandlerService.setAsDefault { _ in
                        isDefault = DefaultHandlerService.isDefault()
                    }
                }
                .disabled(isDefault)
            }
        }
    }

    // MARK: Updates

    @ObservedObject private var updater = UpdaterController.shared

    private var updatesSection: some View {
        Section("Updates") {
            Toggle("Automatically check for updates", isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.automaticallyChecksForUpdates = $0 }))
            HStack {
                Button("Check for Updates Now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                Spacer()
                if let date = updater.lastUpdateCheckDate {
                    Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Export

    private var exportSection: some View {
        Section("Export") {
            HStack {
                Text("Save exports to")
                Spacer()
                Text(settings.exportDirectory.path)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            HStack {
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.prompt = "Choose"
                    if panel.runModal() == .OK, let url = panel.url {
                        settings.exportDirectoryPath = url.path
                    }
                }
                Button("Reset to Default") { settings.exportDirectoryPath = "" }
                    .disabled(settings.exportDirectoryPath.isEmpty)
            }
        }
    }
}

/// A selectable theme swatch card.
private struct ThemeSwatch: View {
    let theme: RenderTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(background)
                    .frame(width: 80, height: 52)
                    .overlay(
                        VStack(alignment: .leading, spacing: 4) {
                            Capsule().fill(accent).frame(width: 36, height: 4)
                            Capsule().fill(.white.opacity(0.5)).frame(width: 48, height: 3)
                            Capsule().fill(.white.opacity(0.35)).frame(width: 30, height: 3)
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                Text(theme.displayName).font(.caption2)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        switch theme {
        case .default:   return Color(red: 0.118, green: 0.118, blue: 0.122)
        case .nord:      return Color(red: 0.180, green: 0.204, blue: 0.251)
        case .solarized: return Color(red: 0.0, green: 0.169, blue: 0.212)
        case .oneDark:   return Color(red: 0.157, green: 0.173, blue: 0.204)
        }
    }
    private var accent: Color {
        switch theme {
        case .default:   return Color(red: 0.43, green: 0.66, blue: 0.99)
        case .nord:      return Color(red: 0.53, green: 0.75, blue: 0.82)
        case .solarized: return Color(red: 0.15, green: 0.55, blue: 0.82)
        case .oneDark:   return Color(red: 0.38, green: 0.69, blue: 0.94)
        }
    }
}

/// Backup settings + recent-archive list (the auto-backup standard's UI).
private struct BackupSection: View {
    @ObservedObject var settings: AppSettings
    @State private var backups: [(url: URL, modified: Date, size: Int)] = []
    @State private var status: String = ""

    var body: some View {
        Section("Backup") {
            Toggle("Back up on launch", isOn: Binding(
                get: { settings.autoBackupEnabled }, set: { settings.autoBackupEnabled = $0 }))
            Stepper("Keep backups for \(settings.backupRetentionDays) days",
                    value: Binding(get: { settings.backupRetentionDays },
                                   set: { settings.backupRetentionDays = $0 }),
                    in: 1...365)
            HStack {
                Text("Backup folder")
                Spacer()
                Text(BackupService.resolvedBackupDirectory(settings).path)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            HStack {
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.prompt = "Choose"
                    if panel.runModal() == .OK, let url = panel.url {
                        settings.backupDirectoryPath = url.path
                        refresh()
                    }
                }
                Button("Run Backup Now") {
                    do { _ = try BackupService.doBackup(settings: settings); status = "Backup complete." }
                    catch { status = "Backup failed: \(error.localizedDescription)" }
                    refresh()
                }
                if !status.isEmpty {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !backups.isEmpty {
                ForEach(backups.prefix(5), id: \.url) { b in
                    HStack {
                        Image(systemName: "doc.zipper").foregroundStyle(.secondary)
                        Text(b.url.lastPathComponent).font(.caption)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64(b.size), countStyle: .file))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        backups = BackupService.listBackups(in: BackupService.resolvedBackupDirectory(settings))
    }
}
