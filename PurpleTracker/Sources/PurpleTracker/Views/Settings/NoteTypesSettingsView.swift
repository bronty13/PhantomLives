import SwiftUI

/// Manage the list of Note Types. Add / rename / reorder / delete. Deletion
/// is blocked at the service layer when live notes exist for the type — the
/// user must trash or re-home those notes first.
struct NoteTypesSettingsView: View {
    @EnvironmentObject var app: AppState
    @State private var newName = ""
    @State private var renameId: String?
    @State private var renameText = ""
    @State private var deleteError: String?

    var body: some View {
        Form {
            Section("Add Note Type") {
                HStack {
                    TextField("New type name", text: $newName)
                    Button("Add") { addType() }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section("Configured Types") {
                List {
                    ForEach(app.noteTypes) { t in
                        HStack {
                            if renameId == t.id {
                                TextField("Name", text: $renameText, onCommit: { commitRename(t) })
                                Button("Save") { commitRename(t) }
                                Button("Cancel") { renameId = nil }
                            } else {
                                Text(t.name)
                                Spacer()
                                Button("Rename") {
                                    renameId = t.id
                                    renameText = t.name
                                }
                                Button(role: .destructive) {
                                    delete(t)
                                } label: { Image(systemName: "trash") }
                            }
                        }
                    }
                    .onMove { idx, dest in
                        var ordered = app.noteTypes
                        ordered.move(fromOffsets: idx, toOffset: dest)
                        do { try app.reorderNoteTypes(ordered) }
                        catch { app.errorMessage = error.localizedDescription }
                    }
                }
                .frame(minHeight: 220)
            }
        }
        .padding()
        .alert("Cannot Delete Note Type",
               isPresented: Binding(get: { deleteError != nil },
                                    set: { if !$0 { deleteError = nil } })) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    private func addType() {
        do {
            _ = try app.addNoteType(name: newName.trimmingCharacters(in: .whitespaces))
            newName = ""
        } catch { app.errorMessage = error.localizedDescription }
    }

    private func commitRename(_ t: NoteType) {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { renameId = nil; return }
        do {
            try app.renameNoteType(id: t.id, to: name)
            renameId = nil
        } catch { app.errorMessage = error.localizedDescription }
    }

    private func delete(_ t: NoteType) {
        do {
            try app.deleteNoteType(id: t.id)
        } catch let e as NoteTypeError {
            switch e {
            case .hasLiveNotes:
                deleteError = "\"\(t.name)\" still has notes. Delete or move those notes first."
            }
        } catch { app.errorMessage = error.localizedDescription }
    }
}
