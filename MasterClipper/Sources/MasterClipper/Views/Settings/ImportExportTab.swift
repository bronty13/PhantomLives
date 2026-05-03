import SwiftUI

struct ImportExportTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var pickedDir: String = ""

    var body: some View {
        Form {
            Section("Default export directory") {
                Text("Used as the starting directory for all exports. Defaults to `~/Downloads/MasterClipper/` if empty.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("(default: ~/Downloads/MasterClipper)", text: Binding(
                        get: { appState.settings.defaultExportDirectory },
                        set: { var s = appState.settings; s.defaultExportDirectory = $0; appState.settings = s }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Button("Choose…") { chooseDir() }
                }
                Text("Resolved: \(appState.settingsStore.resolvedExportDirectory.path)")
                    .font(.caption.monospaced()).foregroundStyle(.tertiary)
            }

            Section("Import") {
                Picker("Duplicate strategy", selection: Binding(
                    get: { appState.settings.importDuplicateStrategy },
                    set: { var s = appState.settings; s.importDuplicateStrategy = $0; appState.settings = s }
                )) {
                    Text("Skip duplicates").tag("skip")
                    Text("Update existing").tag("update")
                    Text("Always insert").tag("insert")
                }

                Toggle("Include notes in global search", isOn: Binding(
                    get: { appState.settings.includeNotesInGlobalSearch },
                    set: { var s = appState.settings; s.includeNotesInGlobalSearch = $0; appState.settings = s }
                ))
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
}
