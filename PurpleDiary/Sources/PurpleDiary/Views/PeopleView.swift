import SwiftUI

/// Manage the global people list. Add / rename / delete people; the editor
/// links them to individual entries. Phase-2 will add a per-person entry feed.
struct PeopleView: View {
    @EnvironmentObject private var appState: AppState
    @State private var newName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            addRow
            Divider()
            if appState.people.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(appState.people) { person in
                        PersonRow(person: person)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var addRow: some View {
        HStack {
            Image(systemName: "person.crop.circle.badge.plus").foregroundStyle(.secondary)
            TextField("Add a person…", text: $newName, prompt: Text("Add a person…"))
                .textFieldStyle(.plain)
                .onSubmit(add)
            Button("Add", action: add)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "person.2")
                .font(.system(size: 32)).foregroundStyle(.secondary)
            Text("No people yet. Add the recurring characters of your life.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        _ = try? appState.createPerson(name: name)
        newName = ""
    }
}

private struct PersonRow: View {
    @EnvironmentObject private var appState: AppState
    let person: Person
    @State private var editingName: String = ""
    @State private var isEditing = false

    var body: some View {
        HStack {
            Image(systemName: "person.circle.fill").foregroundStyle(.secondary)
            if isEditing {
                TextField("Name", text: $editingName, onCommit: commit)
                    .textFieldStyle(.roundedBorder)
            } else {
                Text(person.name.isEmpty ? "Unnamed" : person.name)
            }
            Spacer()
            Button {
                if isEditing { commit() } else { editingName = person.name; isEditing = true }
            } label: {
                Image(systemName: isEditing ? "checkmark" : "pencil")
            }
            .buttonStyle(.plain)
            Button(role: .destructive) {
                try? appState.deletePerson(id: person.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
    }

    private func commit() {
        var p = person
        p.name = editingName.trimmingCharacters(in: .whitespaces)
        try? appState.updatePerson(p)
        isEditing = false
    }
}
