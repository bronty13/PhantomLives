import SwiftUI

/// Step 6 — last chance to back out. Summarizes target type, row
/// count, and the upsert strategy. Lets the user name the mapping
/// in case they didn't earlier (also saveable via the footer's
/// "Save Mapping" button).
struct ConfirmStep: View {
    @ObservedObject var model: ImportWizardModel
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ready to import").font(.title3).bold()

            Form {
                Section {
                    HStack {
                        Text("Mapping name")
                        Spacer()
                        TextField("Untitled mapping", text: $model.draft.name)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 300)
                    }
                }

                Section("What's about to happen") {
                    summaryRow(label: "Source", value: model.pickedFilename ?? "(unknown)")
                    summaryRow(label: "Format", value: model.draft.sourceFormat.displayName)
                    summaryRow(label: "Target", value: targetLabel)
                    summaryRow(label: "Rows in sample", value: "\(model.preview?.sampleRows.count ?? 0)")
                    summaryRow(label: "Field mappings", value: "\(model.draft.fieldMappings.count)")
                    summaryRow(label: "Re-import behavior",
                               value: model.draft.upsertStrategy == .upsertOnKey
                                ? "Upsert on \(model.draft.keyFieldKey ?? "?")"
                                : "Insert every row")
                }

                Section {
                    Text("Imports above \(PurpleImport.bulkThreshold) rows use the bulk path: one undo entry, one deferred CloudKit fan-out at the end, one FTS reindex. Below that, each row writes individually so per-row errors show up live.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .padding(20)
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body)
        }
    }

    private var targetLabel: String {
        if let id = model.draft.targetTypeId, let t = appState.schema.type(id: id) {
            return t.name
        }
        if let t = model.draft.newTypeTemplate {
            return "\(t.name) (new)"
        }
        return "—"
    }
}
