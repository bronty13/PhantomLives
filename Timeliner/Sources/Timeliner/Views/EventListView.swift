import SwiftUI

/// Tabular event view for the case-detail "Events" tab. Sortable columns,
/// editable rows on double-click.
struct EventListView: View {
    @EnvironmentObject private var appState: AppState
    let caseId: String

    @State private var sortOrder: [KeyPathComparator<Event>] = [
        .init(\Event.dateStart, order: .forward)
    ]
    @State private var selection: Event.ID?
    @State private var editingEvent: Event?

    var body: some View {
        Table(events, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.dateStart) { ev in
                Text(ev.parsedStart?.formatted(date: .abbreviated, time: .shortened) ?? ev.dateStart)
                    .font(.callout.monospacedDigit())
            }
            .width(min: 140)

            TableColumn("Title", value: \.title) { ev in
                Text(ev.title.isEmpty ? "Untitled event" : ev.title)
            }

            TableColumn("Importance", value: \.importance) { ev in
                ImportanceBadge(importance: ev.importanceEnum)
            }
            .width(min: 80, max: 120)

            TableColumn("Tags") { ev in
                HStack(spacing: 4) {
                    ForEach(appState.tagsByEvent[ev.id] ?? []) { TagChip(tag: $0, compact: true) }
                }
            }

            TableColumn("Source") { ev in
                if !ev.sourceURL.isEmpty {
                    Text(ev.sourceURL)
                        .lineLimit(1)
                        .foregroundStyle(.tint)
                }
            }
        }
        .contextMenu(forSelectionType: Event.ID.self) { ids in
            if let id = ids.first, let ev = events.first(where: { $0.id == id }) {
                Button("Edit Event") { editingEvent = ev }
                Button("Delete Event", role: .destructive) {
                    try? appState.deleteEvent(id: ev.id)
                }
            }
        } primaryAction: { ids in
            if let id = ids.first, let ev = events.first(where: { $0.id == id }) {
                editingEvent = ev
            }
        }
        .sheet(item: $editingEvent) { ev in
            EventEditorSheet(event: ev, isNew: false).environmentObject(appState)
        }
    }

    private var events: [Event] {
        appState.events
            .filter { $0.caseId == caseId }
            .sorted(using: sortOrder)
    }
}
