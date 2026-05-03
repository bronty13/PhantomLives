import SwiftUI

struct SitesSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    @State private var draft: Site = Site(id: nil, code: "", displayName: "",
                                          personaScope: "", sortOrder: 0, archived: false)
    @State private var draftScope: Set<String> = []
    @State private var editingId: Int64?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sites")
                .font(.title3.weight(.semibold))
            Text("Each site applies to one or more personas. Codes are short keys (\"c4s\"); persona scope is a set of persona codes (e.g. CoC, PoA). Posting checkboxes on each clip filter by this scope.")
                .font(.caption).foregroundStyle(.secondary)

            Table(appState.sites) {
                TableColumn("Code") { s in
                    Text(s.code).font(.body.monospaced())
                }
                .width(min: 60, ideal: 70)

                TableColumn("Display name") { s in
                    Text(s.displayName)
                }

                TableColumn("Persona scope") { s in
                    Text(s.personaScope.isEmpty ? "—" : s.personaScope)
                        .foregroundStyle(s.personaScope.isEmpty ? .tertiary : .primary)
                }

                TableColumn("Order") { s in
                    Text("\(s.sortOrder)").font(.caption.monospacedDigit())
                }
                .width(min: 50, ideal: 60)

                TableColumn("Archived") { s in
                    Image(systemName: s.archived ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(s.archived ? .secondary : .tertiary)
                }
                .width(min: 70, ideal: 80)

                TableColumn("") { s in
                    HStack(spacing: 4) {
                        Button {
                            startEditing(s)
                        } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)

                        Button(role: .destructive) {
                            if let id = s.id { try? appState.deleteSite(id: id) }
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    }
                }
                .width(80)
            }
            .frame(minHeight: 200)

            Divider()

            Form {
                TextField("Code", text: $draft.code).textFieldStyle(.roundedBorder)
                TextField("Display name", text: $draft.displayName).textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Persona scope")
                    HStack {
                        ForEach(appState.personas) { p in
                            Toggle(p.code, isOn: Binding(
                                get: { draftScope.contains(p.code) },
                                set: { newVal in
                                    if newVal { draftScope.insert(p.code) }
                                    else { draftScope.remove(p.code) }
                                }
                            ))
                            .toggleStyle(.checkbox)
                        }
                    }
                }

                Stepper("Sort order: \(draft.sortOrder)", value: $draft.sortOrder, in: 0...999)
                Toggle("Archived", isOn: $draft.archived)
            }
            .formStyle(.grouped)

            HStack {
                if let e = error { Text(e).font(.caption).foregroundStyle(.red) }
                Spacer()
                if editingId != nil {
                    Button("Cancel") { reset() }
                }
                Button(editingId == nil ? "Add" : "Save") {
                    persist()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(draft.code.trimmingCharacters(in: .whitespaces).isEmpty
                          || draft.displayName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private func startEditing(_ s: Site) {
        draft = s
        draftScope = Set(s.personaScopeList)
        editingId = s.id
    }

    private func reset() {
        draft = Site(id: nil, code: "", displayName: "",
                     personaScope: "", sortOrder: 0, archived: false)
        draftScope = []
        editingId = nil
    }

    private func persist() {
        do {
            var copy = draft
            copy.personaScope = draftScope.sorted().joined(separator: ",")
            try appState.saveSite(copy)
            reset()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
