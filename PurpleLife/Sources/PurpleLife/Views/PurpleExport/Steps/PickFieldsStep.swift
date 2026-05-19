import SwiftUI

/// Step 3 — pick the fields to include + override the header
/// (column / property name) for each. Defaults to "include all
/// fields in schema order, headers = field names" so a user who
/// just wants a quick dump can skip this step.
struct PickFieldsStep: View {
    @ObservedObject var model: ExportWizardModel
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Fields + headers").font(.title3).bold()
                Spacer()
                Button {
                    seedFromType()
                } label: {
                    Label("Reset to all fields", systemImage: "arrow.counterclockwise")
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 20).padding(.top, 16)

            ScrollView {
                VStack(spacing: 0) {
                    headerRow
                    Divider()
                    ForEach(model.draft.fields.indices, id: \.self) { idx in
                        fieldRow(idx)
                        Divider().opacity(0.3)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
        .onAppear { seedIfEmpty() }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            label("Include", width: 70)
            label("Field key", width: 180)
            label("→", width: 16)
            label("Header (column / property name)", width: 280)
            label("Kind", width: 120)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
    }

    private func label(_ s: String, width: CGFloat) -> some View {
        Text(s)
            .font(.caption.weight(.semibold)).tracking(0.4)
            .textCase(.uppercase).foregroundStyle(.tertiary)
            .frame(width: width, alignment: .leading)
    }

    // MARK: - Row

    private func fieldRow(_ idx: Int) -> some View {
        let sel = model.draft.fields[idx]
        // Look up the schema field for kind display.
        let info = lookupFieldInfo(key: sel.fieldKey)
        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { true },
                set: { keep in
                    if !keep {
                        // Soft-delete: yank the row from the export
                        // list. The user can hit "Reset to all
                        // fields" to bring everything back.
                        model.draft.fields.remove(at: idx)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .frame(width: 70, alignment: .leading)

            Text(sel.fieldKey)
                .font(.body.monospaced())
                .frame(width: 180, alignment: .leading)

            Text("→").foregroundStyle(.tertiary).frame(width: 16)

            TextField("column name", text: Binding(
                get: { model.draft.fields[idx].header },
                set: { model.draft.fields[idx].header = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 280)

            HStack(spacing: 4) {
                Image(systemName: info?.kind.systemImage ?? "circle")
                    .foregroundStyle(.tertiary)
                Text(info?.kind.displayName ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 120, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func lookupFieldInfo(key: String) -> SourceFieldInfo? {
        guard let id = model.draft.typeId,
              let infos = try? model.source.listFields(typeId: id) else { return nil }
        return infos.first(where: { $0.key == key })
    }

    private func seedIfEmpty() {
        guard model.draft.fields.isEmpty else { return }
        seedFromType()
    }

    private func seedFromType() {
        guard let id = model.draft.typeId,
              let infos = try? model.source.listFields(typeId: id) else { return }
        model.draft.fields = infos.map { f in
            PurpleExport.FieldSelection(
                id: UUID().uuidString,
                fieldKey: f.key,
                header: f.name
            )
        }
    }
}
