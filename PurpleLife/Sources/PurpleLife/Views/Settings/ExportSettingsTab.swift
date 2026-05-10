import AppKit
import SwiftUI

/// Settings → Export. Lets the user override where the per-type Export
/// menu writes its files. Default is `~/Downloads/PurpleLife/` per the
/// PhantomLives convention; overrides persist in `settings.json` and
/// stick across launches.
struct ExportSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Default export directory") {
                Text("Used by Records → Export menu (CSV / Markdown / HTML / PDF). Files are written as `<TypeName>-YYYY-MM-DD-HHmmss.<ext>`. Leave blank for the default.")
                    .font(.caption).foregroundStyle(.secondary)

                HStack {
                    TextField("(default: ~/Downloads/PurpleLife)", text: Binding(
                        get: { appState.settings.defaultExportDirectory },
                        set: { var s = appState.settings; s.defaultExportDirectory = $0; appState.settings = s }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseDir() }
                    Button("Reveal") { reveal() }
                        .disabled(!FileManager.default.fileExists(atPath: appState.settingsStore.resolvedExportDirectory.path))
                }

                Text("Resolved: \(appState.settingsStore.resolvedExportDirectory.path)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private func chooseDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            var s = appState.settings
            s.defaultExportDirectory = url.path
            appState.settings = s
        }
    }

    private func reveal() {
        let url = appState.settingsStore.resolvedExportDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
