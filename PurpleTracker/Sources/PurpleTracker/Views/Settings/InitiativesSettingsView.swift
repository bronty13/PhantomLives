import SwiftUI

/// Configurable list of strategic Initiatives a Matter can be tagged with.
/// Each row binds to a single `Initiative`. Edits commit on submit / focus
/// loss to keep the row in sync with the DB.
struct InitiativesSettingsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Initiatives").font(.headline)
                Spacer()
                Button {
                    let new = Initiative(
                        id: UUID().uuidString,
                        name: "New Initiative",
                        sortOrder: (app.initiatives.map(\.sortOrder).max() ?? 0) + 1
                    )
                    try? app.saveInitiative(new)
                } label: { Label("Add", systemImage: "plus") }
            }
            Text("Tag Matters with one or more strategic initiatives. Manage on the Matter's Overview tab.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                ForEach(app.initiatives) { i in
                    InitiativeRow(initiative: i)
                    Divider()
                }
            }
        }
    }
}

private struct InitiativeRow: View {
    let initiative: Initiative
    @EnvironmentObject var app: AppState
    @State private var name: String = ""
    @State private var loaded = false

    var body: some View {
        HStack {
            Image(systemName: "flag.fill")
                .foregroundStyle(.purple)
                .frame(width: 20)
            TextField("", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    var i = initiative; i.name = name; try? app.saveInitiative(i)
                }
            Button(role: .destructive) {
                try? app.deleteInitiative(id: initiative.id)
            } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .help("Remove this initiative. Existing tags on Matters are also removed.")
        }
        .padding(.vertical, 4)
        .onAppear {
            guard !loaded else { return }
            name = initiative.name
            loaded = true
        }
    }
}
