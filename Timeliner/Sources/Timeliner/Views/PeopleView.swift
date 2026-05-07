import SwiftUI

/// People tab inside a case detail view.
struct CasePeopleView: View {
    @EnvironmentObject private var appState: AppState
    let caseId: String

    @State private var editingPerson: Person?
    @State private var roleFilter: PersonRole?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("", selection: $roleFilter) {
                    Text("All roles").tag(PersonRole?.none)
                    ForEach(PersonRole.allCases, id: \.self) { r in
                        Text(r.label).tag(PersonRole?.some(r))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 180)

                Spacer()

                Button {
                    let p = (try? appState.createPerson(caseId: caseId)) ?? nil
                    editingPerson = p
                } label: {
                    Label("Add Person", systemImage: "person.fill.badge.plus")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if filtered.isEmpty {
                Spacer()
                Text(people.isEmpty
                     ? "No people on this case yet."
                     : "No people match this filter.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)],
                               spacing: 12) {
                        ForEach(filtered) { p in
                            PersonCard(person: p,
                                        colorHex: appState.settingsStore.roleColorHex(for: p.roleEnum)) {
                                editingPerson = p
                            } onDelete: {
                                try? appState.deletePerson(id: p.id)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .sheet(item: $editingPerson) { p in
            PersonEditorSheet(person: p).environmentObject(appState)
        }
    }

    private var people: [Person] {
        appState.people.filter { $0.caseId == caseId }
    }

    private var filtered: [Person] {
        guard let r = roleFilter else { return people }
        return people.filter { $0.roleEnum == r }
    }
}

/// Sidebar "People" section — flat global list across all cases.
struct GlobalPeopleView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Table(appState.people) {
            TableColumn("Name") { p in
                Text(p.name.isEmpty ? "Unnamed" : p.name)
            }
            TableColumn("Role") { p in
                PersonRoleChip(person: p,
                                colorHex: appState.settingsStore.roleColorHex(for: p.roleEnum))
            }
            TableColumn("Case") { p in
                if let title = appState.cases.first(where: { $0.id == p.caseId })?.title {
                    Text(title)
                }
            }
            TableColumn("Notes") { p in
                Text(p.notes).lineLimit(2).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("People")
    }
}

private struct PersonCard: View {
    let person: Person
    let colorHex: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    PersonRoleChip(person: person, colorHex: colorHex)
                    Spacer()
                }
                Text(person.name.isEmpty ? "Unnamed" : person.name)
                    .font(.title3.weight(.semibold))
                if !person.notes.isEmpty {
                    Text(person.notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(.background.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit", action: onEdit)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

struct PersonEditorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State var person: Person

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(person.name.isEmpty ? "New Person" : "Edit Person")
                .font(.title2.weight(.semibold))
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Form {
                        TextField("Name", text: $person.name)
                            .textFieldStyle(.roundedBorder)
                        Picker("Role", selection: Binding(
                            get: { person.roleEnum },
                            set: { person.roleEnum = $0 }
                        )) {
                            ForEach(PersonRole.allCases, id: \.self) { r in
                                Text(r.label).tag(r)
                            }
                        }
                        TextEditor(text: $person.notes)
                            .frame(minHeight: 120, maxHeight: 220)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.4)))
                    }
                    .formStyle(.grouped)
                    AttachmentList(parent: .person, parentId: person.id)
                        .padding(.horizontal, 4)
                }
                .padding(20)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    try? appState.updatePerson(person)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(minWidth: 540, idealWidth: 620, maxWidth: 820,
               minHeight: 460, idealHeight: 540, maxHeight: 780)
    }
}
