import SwiftUI

/// Step 2 — pick which records of the type to include. Phase 4
/// supports `.all`; the saved-search option is staged grey for now.
struct PickRecordsStep: View {
    @ObservedObject var model: ExportWizardModel
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Which records?") {
                Picker("Records", selection: selectorBinding) {
                    Text("All records of this type").tag("all")
                    Text("Saved search (Phase 4.5)").tag("savedSearch").disabled(true)
                }
                .pickerStyle(.inline)
            }
            if let id = model.draft.typeId,
               let type = appState.schema.type(id: id) {
                let count = (try? ObjectEngine.fetch(typeId: id).count) ?? 0
                Section {
                    HStack {
                        Image(systemName: type.systemImage).foregroundStyle(.secondary)
                        Text("\(type.pluralName)").font(.body)
                        Spacer()
                        Text("\(count) record\(count == 1 ? "" : "s") available")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private var selectorBinding: Binding<String> {
        Binding(
            get: {
                switch model.draft.selector {
                case .all:          return "all"
                case .savedSearch:  return "savedSearch"
                }
            },
            set: { newVal in
                if newVal == "all" { model.draft.selector = .all }
            }
        )
    }
}
