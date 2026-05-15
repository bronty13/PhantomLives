import SwiftUI
import AppKit

/// SlackSucker's preferences window. Modeled after messages-exporter-gui:
/// one long scrollable pane rather than separate tabs, so settings stay
/// discoverable without UI chrome to navigate.
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var runner: ArchiveRunner

    @AppStorage("themePreference") private var themePref: String = ThemePreference.system.rawValue
    @AppStorage("debugLogging") private var debugLogging: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                outputSection
                defaultsSection
                appearanceSection
                diagnosticsSection
                BackupSettingsView()
            }
            .padding(20)
        }
        .frame(minWidth: 540, minHeight: 560)
    }

    @ViewBuilder
    private var outputSection: some View {
        section(title: "OUTPUT FOLDER") {
            HStack {
                TextField("Default: ~/Downloads/SlackSucker",
                          text: Binding(get: { settings.outputDirOverride ?? "" },
                                        set: { settings.outputDirOverride = $0.isEmpty ? nil : $0
                                               settings.save() }))
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") { chooseOutputDir() }
            }
            Text("Resolved: \(settings.resolvedOutputDir.path)")
                .font(AppFont.mono(10))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var defaultsSection: some View {
        section(title: "DEFAULT ARCHIVE OPTIONS") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Download files", isOn: Binding(
                    get: { settings.defaultArchiveOptions.includeFiles },
                    set: { settings.defaultArchiveOptions.includeFiles = $0; settings.save() }))
                Toggle("Download avatars", isOn: Binding(
                    get: { settings.defaultArchiveOptions.includeAvatars },
                    set: { settings.defaultArchiveOptions.includeAvatars = $0; settings.save() }))
                Toggle("Member-only channels (workspace-wide runs)", isOn: Binding(
                    get: { settings.defaultArchiveOptions.memberOnly },
                    set: { settings.defaultArchiveOptions.memberOnly = $0; settings.save() }))
                Toggle("Sort attachments into Videos / Photos / Audio / Other", isOn: Binding(
                    get: { settings.defaultArchiveOptions.organizeFiles },
                    set: { settings.defaultArchiveOptions.organizeFiles = $0; settings.save() }))
                Text("When on, attachments are moved out of slackdump's \u{201C}__uploads/<ID>/\u{201D} layout into category subfolders at the run-folder root. The SQLite database and avatar thumbnails are untouched.")
                    .font(AppFont.sans(11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        section(title: "APPEARANCE") {
            Picker("Theme", selection: $themePref) {
                ForEach(ThemePreference.allCases) { t in
                    Text(t.label).tag(t.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        section(title: "DIAGNOSTICS") {
            Toggle("Verbose slackdump output (-v)", isOn: $debugLogging)
            Text("Slack workspace credentials live in ~/Library/Caches/slackdump, owned and encrypted by slackdump itself.")
                .font(AppFont.sans(11))
                .foregroundStyle(.tertiary)
        }
    }

    private func chooseOutputDir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = settings.resolvedOutputDir
        if panel.runModal() == .OK, let url = panel.url {
            settings.outputDirOverride = url.path
            settings.save()
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppFont.kicker())
                .foregroundStyle(.secondary)
            content()
        }
    }
}
