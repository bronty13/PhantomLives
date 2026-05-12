import SwiftUI

/// Left pane of the Notes workspace — search bar, +button, date-grouped
/// rows. Mirrors PurpleTracker's `NotesListView` shape.
struct NotesListView: View {
    let type: ObjectType?
    let rows: [ObjectRecord]
    @Binding var selectedNoteId: String?
    @Binding var search: String
    let onCreate: () -> Void
    let onDelete: (ObjectRecord) -> Void

    private var primaryKey: String { type?.primaryFieldKey ?? "title" }
    private var dateKey: String { type?.calendarDateKey ?? "date" }
    private var bodyKey: String {
        type?.fields.first(where: { $0.kind == .richText })?.key ?? "body"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(type?.pluralName ?? "Notes").font(.headline)
                Spacer()
                Button(action: onCreate) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New note (⌘N)")
            }
            .padding(.horizontal).padding(.vertical, 8)

            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal).padding(.bottom, 6)

            Divider()

            List(selection: $selectedNoteId) {
                ForEach(grouped, id: \.key) { (date, group) in
                    Section(header: Text(dateHeader(for: date))) {
                        ForEach(group) { row in
                            NoteRow(record: row, primaryKey: primaryKey, bodyKey: bodyKey)
                                .tag(row.id as String?)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        onDelete(row)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    /// Group rows by the calendar day in their date field. Already in
    /// outer order (date desc, updatedAt desc), so a single pass keeps
    /// the section order stable.
    private var grouped: [(key: String, value: [ObjectRecord])] {
        var groups: [String: [ObjectRecord]] = [:]
        var order: [String] = []
        for row in rows {
            let day = (row.fields()[dateKey] as? String).map { String($0.prefix(10)) } ?? ""
            if groups[day] == nil { order.append(day) }
            groups[day, default: []].append(row)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    /// "Today" / "Yesterday" / "Mon, Mar 5" — friendlier than raw ISO
    /// for the section headers.
    private func dateHeader(for iso: String) -> String {
        guard let d = ISO8601DateFormatter.parseDay(iso) else {
            return iso.isEmpty ? "No date" : iso
        }
        let cal = Calendar.current
        if cal.isDateInToday(d)     { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d, yyyy"
        return formatter.string(from: d)
    }
}

private struct NoteRow: View {
    let record: ObjectRecord
    let primaryKey: String
    let bodyKey: String

    private var title: String {
        let s = (record.fields()[primaryKey] as? String) ?? ""
        return s.isEmpty ? "(Untitled)" : s
    }

    private var preview: String {
        guard let dict = record.fields()[bodyKey] as? [String: Any] else { return "" }
        return (dict["plain"] as? String) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body).lineLimit(1)
            if !preview.isEmpty {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - ISO date helpers

extension ISO8601DateFormatter {
    /// Parse a YYYY-MM-DD string into a Date at start-of-day.
    static func parseDay(_ s: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: String(s.prefix(10)))
    }
}
