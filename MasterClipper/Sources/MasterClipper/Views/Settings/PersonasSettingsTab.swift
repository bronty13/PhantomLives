import SwiftUI

struct PersonasSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft: Persona = Persona(id: nil, code: "", displayName: "",
                                                colorHex: "#888888", sortOrder: 0, archived: false)
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personas")
                .font(.title3.weight(.semibold))
            Text("Codes are short labels (e.g. \"CoC\") that appear in the UI; display names are the long form.")
                .font(.caption).foregroundStyle(.secondary)

            Table(appState.personas) {
                TableColumn("Code") { p in
                    Text(p.code).font(.body.monospaced())
                }
                .width(min: 60, ideal: 70)

                TableColumn("Display name") { p in
                    Text(p.displayName)
                }

                TableColumn("Color") { p in
                    HStack {
                        Circle().fill(Color(hex: p.colorHex) ?? .gray).frame(width: 12, height: 12)
                        Text(p.colorHex).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .width(min: 110, ideal: 130)

                TableColumn("Order") { p in
                    Text("\(p.sortOrder)").font(.caption.monospacedDigit())
                }
                .width(min: 50, ideal: 60)

                TableColumn("Archived") { p in
                    Image(systemName: p.archived ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(p.archived ? .secondary : .tertiary)
                }
                .width(min: 70, ideal: 80)

                TableColumn("") { p in
                    Button(role: .destructive) {
                        delete(p)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .width(40)
            }
            .frame(minHeight: 180)

            Divider()

            Form {
                TextField("Code", text: $draft.code).textFieldStyle(.roundedBorder)
                TextField("Display name", text: $draft.displayName).textFieldStyle(.roundedBorder)
                ColorPicker(selection: Binding(
                    get: { Color(hex: draft.colorHex) ?? .gray },
                    set: { newColor in
                        if let hex = newColor.toHex() { draft.colorHex = hex }
                    }
                ), supportsOpacity: false) {
                    HStack {
                        Text("Color")
                        Text(draft.colorHex)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
                Stepper("Sort order: \(draft.sortOrder)", value: $draft.sortOrder, in: 0...999)
                Toggle("Archived", isOn: $draft.archived)
            }
            .formStyle(.grouped)

            HStack {
                if let e = error { Text(e).font(.caption).foregroundStyle(.red) }
                Spacer()
                Button("Add / save", action: addOrSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.code.trimmingCharacters(in: .whitespaces).isEmpty
                              || draft.displayName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private func addOrSave() {
        do {
            try appState.savePersona(draft)
            draft = Persona(id: nil, code: "", displayName: "",
                            colorHex: "#888888", sortOrder: 0, archived: false)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ p: Persona) {
        guard let id = p.id else { return }
        do {
            try appState.deletePersona(id: id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
