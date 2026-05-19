import SwiftUI

/// Step 6 — last chance to set the destination, name the config,
/// and tweak the filename template.
struct SaveStep: View {
    @ObservedObject var model: ExportWizardModel
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Where should it land?").font(.title3).bold()
            Form {
                Section {
                    HStack {
                        Text("Config name")
                        Spacer()
                        TextField("Untitled export", text: $model.draft.name)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 320)
                    }
                }
                Section("Destination") {
                    Picker("Mode", selection: modeBinding) {
                        Text("Default (~/Downloads/PurpleLife/)").tag("default")
                        Text("Custom path").tag("custom")
                    }
                    .pickerStyle(.menu)
                    if model.draft.destination.mode == .custom {
                        HStack {
                            TextField("Path", text: Binding(
                                get: { model.draft.destination.customPath ?? "" },
                                set: { model.draft.destination.customPath = $0 }
                            ))
                            Button("Choose…") { pickDirectory() }
                        }
                    }
                    HStack {
                        Text("Filename template")
                        Spacer()
                        TextField("{type-plural}-{stamp}.{ext}", text: $model.draft.destination.filenameTemplate)
                            .multilineTextAlignment(.trailing)
                            .font(.body.monospaced())
                            .frame(maxWidth: 360)
                    }
                    Text("Tokens: {type-plural}, {type-name}, {stamp}, {ext}.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text("Resolved path:")
                            .foregroundStyle(.secondary)
                        Text(resolvedPathPreview)
                            .font(.caption.monospaced())
                            .foregroundStyle(.primary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .padding(20)
    }

    private var modeBinding: Binding<String> {
        Binding(
            get: { model.draft.destination.mode == .custom ? "custom" : "default" },
            set: { newVal in
                model.draft.destination.mode = (newVal == "custom") ? .custom : .default
            }
        )
    }

    private var resolvedPathPreview: String {
        let dir: String
        switch model.draft.destination.mode {
        case .default: dir = appState.settingsStore.resolvedExportDirectory.path
        case .custom:  dir = (model.draft.destination.customPath ?? "(empty)")
        }
        let stamp = "YYYY-MM-DD-HHmmss"
        let pluralRaw: String = {
            if let id = model.draft.typeId,
               let t = appState.schema.type(id: id) {
                return t.pluralName.isEmpty ? t.name : t.pluralName
            }
            return "type"
        }()
        let filename = model.draft.destination.filenameTemplate
            .replacingOccurrences(of: "{type-plural}", with: pluralRaw)
            .replacingOccurrences(of: "{type-name}", with: pluralRaw)
            .replacingOccurrences(of: "{stamp}", with: stamp)
            .replacingOccurrences(of: "{ext}", with: model.draft.format.fileExtension)
        return "\(dir)/\(filename)"
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.draft.destination.customPath = url.path
        }
    }
}
