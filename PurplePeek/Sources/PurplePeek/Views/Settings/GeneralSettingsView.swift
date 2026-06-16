import SwiftUI

/// General preferences: default mode, appearance, color theme, and the Kept Audio Export
/// folder. Binds directly to `SettingsStore.settings` (auto-saves on change).
struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Picker("Default mode", selection: $store.settings.defaultMode) {
                ForEach(AppMode.allCases) { Text($0.label).tag($0) }
            }

            Picker("Appearance", selection: $store.settings.appearance) {
                ForEach(AppAppearance.allCases) { Text($0.label).tag($0) }
            }

            Picker("Color theme", selection: $store.settings.themeName) {
                ForEach(AppTheme.all) { theme in
                    HStack {
                        Circle().fill(theme.accentColor).frame(width: 12, height: 12)
                        Text(theme.name)
                    }
                    .tag(theme.name)
                }
            }

            Divider()

            LabeledContent("Kept Audio Export") {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(appState.settingsStore.resolvedKeptAudioPath.path)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    HStack {
                        Button("Change…") { chooseKeptAudioFolder() }
                        Button("Reveal") {
                            NSWorkspace.shared.activateFileViewerSelecting([appState.settingsStore.resolvedKeptAudioPath])
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private func chooseKeptAudioFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            store.settings.keptAudioExportPath = url.path
        }
    }
}
