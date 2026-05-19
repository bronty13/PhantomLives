import SwiftUI

/// Step 3a — define a new type inline. Minimal author UI; the full
/// Schema Editor handles complex shapes.
struct NewTypeFromSourceStep: View {
    @ObservedObject var model: ImportWizardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Define the new type").font(.title3).bold()
                Form {
                    Section {
                        TextField("Singular name", text: binding(\.name))
                        TextField("Plural name", text: binding(\.pluralName))
                        TextField("SF Symbol", text: binding(\.systemImage))
                            .font(.body.monospaced())
                        Toggle("Place in Vault", isOn: binding(\.isVault))
                    }
                    Section("Proposed fields") {
                        if let fields = model.draft.newTypeTemplate?.fields {
                            ForEach(Array(fields.enumerated()), id: \.offset) { idx, _ in
                                HStack(spacing: 10) {
                                    Image(systemName: fields[idx].kind.systemImage)
                                        .frame(width: 18).foregroundStyle(.secondary)
                                    TextField("Name", text: fieldBinding(idx, \.name))
                                    Picker("Kind", selection: fieldBinding(idx, \.kind)) {
                                        ForEach(FieldKind.allCases, id: \.self) { k in
                                            Text(k.displayName).tag(k)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 160)
                                    Toggle("Required", isOn: fieldBinding(idx, \.required))
                                        .toggleStyle(.checkbox)
                                        .labelsHidden()
                                }
                            }
                        } else {
                            Text("No fields proposed — go back and run a source preview.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                .formStyle(.grouped)
            }
            .padding(20)
        }
    }

    // MARK: - Bindings

    private func binding<T>(_ keyPath: WritableKeyPath<SavedImportMapping.NewTypeTemplate, T>) -> Binding<T> {
        Binding(
            get: { model.draft.newTypeTemplate![keyPath: keyPath] },
            set: { newValue in model.draft.newTypeTemplate?[keyPath: keyPath] = newValue }
        )
    }

    private func fieldBinding<T>(_ index: Int, _ keyPath: WritableKeyPath<SavedImportMapping.NewTypeTemplate.ProposedField, T>) -> Binding<T> {
        Binding(
            get: { model.draft.newTypeTemplate!.fields[index][keyPath: keyPath] },
            set: { newValue in model.draft.newTypeTemplate?.fields[index][keyPath: keyPath] = newValue }
        )
    }
}
