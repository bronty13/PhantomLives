import SwiftUI

/// Searchable picker over the People roster. Stores the chosen Person's
/// Associate ID; displays "Name (Title)". Used for Requestor and the five
/// Interested Party slots.
struct PersonPicker: View {
    @Binding var selectedId: String
    var placeholder: String = "Type a name…"
    var clearHelp: String = "Clear"
    @EnvironmentObject var app: AppState

    @State private var query: String = ""
    @State private var showResults = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let p = app.peopleById[selectedId], !selectedId.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.fill")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(p.displayName).font(.body.weight(.medium))
                            if !p.jobTitle.isEmpty {
                                Text(Person.titleCase(p.jobTitle))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.10))
                    .cornerRadius(6)

                    Button {
                        selectedId = ""
                        query = ""
                    } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(clearHelp)
                }

                TextField(selectedId.isEmpty ? placeholder : "Change…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onChange(of: query) { _, _ in
                        showResults = fieldFocused
                    }
                    .onChange(of: fieldFocused) { _, focused in
                        showResults = focused
                    }
            }

            if showResults {
                let matches = filteredPeople
                if matches.isEmpty {
                    Text(app.people.isEmpty
                         ? "No people imported yet — Settings → People → Import CSV."
                         : "No matches.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.leading, 4)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(matches.prefix(8), id: \.id) { p in
                                Button {
                                    selectedId = p.id
                                    query = ""
                                    showResults = false
                                    fieldFocused = false
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(p.displayName).font(.body.weight(.medium))
                                            HStack(spacing: 4) {
                                                if !p.jobTitle.isEmpty {
                                                    Text(Person.titleCase(p.jobTitle))
                                                        .font(.caption).foregroundStyle(.secondary)
                                                }
                                                if !p.department.isEmpty {
                                                    Text("• \(Person.titleCase(p.department))")
                                                        .font(.caption2).foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                        Spacer()
                                        if !p.isActive {
                                            Text(p.positionStatus)
                                                .font(.caption2)
                                                .padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(Color.secondary.opacity(0.15))
                                                .cornerRadius(3)
                                        }
                                    }
                                    .padding(.vertical, 4).padding(.horizontal, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    .cornerRadius(6)
                }
            }
        }
    }

    private var filteredPeople: [Person] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        // Empty query → show top active people so the user can pick without
        // typing anything (handy when they don't remember the spelling).
        if q.isEmpty {
            return Array(
                app.people
                    .filter { $0.isActive }
                    .sorted { ($0.lastName.lowercased(), $0.firstName.lowercased())
                              < ($1.lastName.lowercased(), $1.firstName.lowercased()) }
                    .prefix(50)
            )
        }
        // Active first, then everyone else.
        let scored = app.people.compactMap { p -> (Person, Int)? in
            let name = p.displayName.lowercased()
            let title = p.jobTitle.lowercased()
            let email = p.workEmail.lowercased()
            if name.hasPrefix(q) { return (p, p.isActive ? 0 : 10) }
            if name.contains(q)  { return (p, p.isActive ? 1 : 11) }
            if email.contains(q) { return (p, p.isActive ? 2 : 12) }
            if title.contains(q) { return (p, p.isActive ? 3 : 13) }
            return nil
        }
        return scored.sorted { $0.1 < $1.1 }.map { $0.0 }
    }
}

/// Convenience wrapper preserving the original call sites that picked a Requestor.
struct RequestorPicker: View {
    @Binding var selectedId: String
    var body: some View {
        PersonPicker(selectedId: $selectedId,
                     placeholder: "Type a name…",
                     clearHelp: "Clear requestor")
    }
}
