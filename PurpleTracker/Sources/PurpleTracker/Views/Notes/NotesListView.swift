import SwiftUI

/// Note list for one Note Type. Mirrors the Matter list column: search bar at
/// the top, + button to create a new note, rows grouped by date.
struct NotesListView: View {
    @EnvironmentObject var app: AppState
    let typeId: String
    @State private var search = ""

    private var typeName: String {
        app.noteTypes.first(where: { $0.id == typeId })?.name ?? "Notes"
    }

    private var filtered: [GenericNote] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return app.notesForType }
        return app.notesForType.filter {
            $0.title.lowercased().contains(q) || $0.bodyPlain.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(typeName).font(.headline)
                Spacer()
                Button {
                    _ = try? app.addGenericNote(typeId: typeId)
                } label: { Image(systemName: "plus") }
                    .help("New note")
            }
            .padding(.horizontal).padding(.vertical, 8)
            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal).padding(.bottom, 6)
            Divider()
            List(selection: Binding(
                get: { app.selectedNoteId },
                set: { app.selectedNoteId = $0 }
            )) {
                ForEach(groupedByDate(filtered), id: \.key) { date, notes in
                    Section(header: Text(date, format: .dateTime.year().month().day())) {
                        ForEach(notes) { n in
                            NoteListRow(note: n)
                                .tag(n.id as String?)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        try? app.deleteGenericNote(id: n.id)
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .onAppear { app.selectNoteType(typeId) }
        .onChange(of: typeId) { _, new in app.selectNoteType(new) }
    }

    /// `app.notesForType` is already sorted by note_date desc, so a single
    /// pass keeps each group ordered by `updated_at` desc within the date.
    private func groupedByDate(_ rows: [GenericNote]) -> [(key: Date, value: [GenericNote])] {
        let cal = Calendar.current
        var groups: [Date: [GenericNote]] = [:]
        var order: [Date] = []
        for n in rows {
            let day = cal.startOfDay(for: n.noteDate)
            if groups[day] == nil { order.append(day) }
            groups[day, default: []].append(n)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }
}

private struct NoteListRow: View {
    let note: GenericNote

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.title.isEmpty ? "(Untitled)" : note.title)
                .font(.body)
                .lineLimit(1)
            if !note.bodyPlain.isEmpty {
                Text(note.bodyPlain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
