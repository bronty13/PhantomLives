import SwiftUI

/// Step 3 — choose a target type, either an existing one from the
/// schema registry or a new one defined inline.
struct PickTargetStep: View {
    @ObservedObject var model: ImportWizardModel
    @EnvironmentObject private var appState: AppState

    @State private var creatingNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Where should these records land?").font(.title3).bold()

            Toggle("Create a new type from this source", isOn: $creatingNew)
                .toggleStyle(.switch)
                .onChange(of: creatingNew) { _, newValue in
                    if newValue {
                        if model.draft.newTypeTemplate == nil {
                            model.draft.newTypeTemplate = makeTemplate()
                        }
                        model.draft.targetTypeId = nil
                    } else {
                        model.draft.newTypeTemplate = nil
                    }
                }

            if !creatingNew {
                List(selection: $model.draft.targetTypeId) {
                    ForEach(appState.schema.visibleTypes, id: \.id) { t in
                        HStack(spacing: 10) {
                            Image(systemName: t.systemImage)
                                .frame(width: 18)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.name).font(.body)
                                Text("\(t.fields.count) field\(t.fields.count == 1 ? "" : "s")")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if t.isVault {
                                Text("Vault").font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Color.purple.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                        .tag(t.id as String?)
                    }
                }
                .frame(minHeight: 220)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.green)
                    Text("Next step: name the new type.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .onAppear { creatingNew = model.draft.newTypeTemplate != nil }
    }

    private func makeTemplate() -> SavedImportMapping.NewTypeTemplate {
        // Seed proposed fields from the current preview if we have one.
        var fields: [SavedImportMapping.NewTypeTemplate.ProposedField] = []
        if let p = model.preview {
            switch p.shape {
            case .tabular(let columns, let kinds):
                fields = columns.map { col in
                    SavedImportMapping.NewTypeTemplate.ProposedField(
                        name: col,
                        kind: kinds[col] ?? .text,
                        required: false,
                        options: []
                    )
                }
            case .tree(let paths):
                fields = paths.map { p in
                    let name = p.split(separator: ".").last.map(String.init) ?? p
                    return SavedImportMapping.NewTypeTemplate.ProposedField(
                        name: name,
                        kind: .text,
                        required: false,
                        options: []
                    )
                }
            case .document:
                fields = [.init(name: "Body", kind: .longText, required: false, options: [])]
            }
        }
        return SavedImportMapping.NewTypeTemplate(
            name: "Imported",
            pluralName: "Imported",
            systemImage: "tray.full",
            colorHex: "#7B5CD6",
            isVault: false,
            fields: fields
        )
    }
}
