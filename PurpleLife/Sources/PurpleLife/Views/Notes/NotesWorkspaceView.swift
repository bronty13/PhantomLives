import SwiftUI

/// Two-pane Notes workspace: date-grouped list on the left, editor on
/// the right. Replaces the standard `RecordsScreen` for the `Note`
/// type — the UX matches PurpleTracker's v1.5 Notes feature.
///
/// The Note type is just a regular `ObjectType` underneath: records go
/// through `ObjectEngine`, the body field is a `.richText` value inside
/// `fields_json`, sync rides the same `encryptedValues["fieldsJSON"]`
/// path as every other record. Only the UX is different.
struct NotesWorkspaceView: View {
    @EnvironmentObject private var appState: AppState

    /// Note type id. The view is constructed by `ContentView` when the
    /// active selection is the Note type, but accept it as a parameter
    /// so the type id stays explicit (and a future "Personal Journal"
    /// type using the same view could be wired in too).
    let typeId: String

    @State private var notes: [ObjectRecord] = []
    @State private var selectedNoteId: String?
    @State private var search: String = ""
    @State private var error: String?

    private var type: ObjectType? {
        appState.schema.type(id: typeId)
    }

    private var filtered: [ObjectRecord] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return notes }
        return notes.filter { n in
            let title = (n.fields()[primaryKey] as? String)?.lowercased() ?? ""
            let plain = ((n.fields()[bodyKey] as? [String: Any])?["plain"] as? String)?.lowercased() ?? ""
            return title.contains(q) || plain.contains(q)
        }
    }

    private var primaryKey: String { type?.primaryFieldKey ?? "title" }
    private var bodyKey: String {
        type?.fields.first(where: { $0.kind == .richText })?.key ?? "body"
    }

    var body: some View {
        // Plain HStack instead of `HSplitView` — backlog #15
        // (2026-05-15) traced the broken Notes layout to a
        // SwiftUI / AppKit bridge bug: NSSplitView (which
        // HSplitView wraps) keeps its own copy of subview frames
        // separately from SwiftUI's declared min/ideal/max
        // constraints, autosaves them to UserDefaults under a
        // synthesized key, and rewrites them at app quit even if
        // we wipe at launch (which `AppDelegate` already does).
        // When the autosaved sum-of-widths exceeds the current
        // window, AppKit lays the panes out at the saved widths,
        // which squeezes the outer NavigationSplitView's sidebar
        // below its declared minimum and clips its labels —
        // exactly the screenshot. Replacing the inner HSplitView
        // with a fixed-width HStack eliminates NSSplitView from
        // this view tree entirely, so the broken autosaved-frame
        // path can't recur. Trade-off: the inner splitter is no
        // longer user-draggable; the existing one was broken
        // anyway. The outer NavigationSplitView splitter still
        // works for the main app sidebar.
        HStack(spacing: 0) {
            NotesListView(
                type: type,
                rows: filtered,
                selectedNoteId: $selectedNoteId,
                search: $search,
                onCreate: createNote,
                onDelete: deleteNote
            )
            .frame(width: 300)

            Divider()

            Group {
                if let id = selectedNoteId,
                   let note = notes.first(where: { $0.id == id }),
                   let t = type {
                    NoteEditorView(note: note, type: t, onChanged: reload)
                        .id(id)
                } else {
                    placeholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { createNote() } label: { Label("New note", systemImage: "plus") }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(
            for: AppState.objectsChangedRemotelyNotification
        )) { _ in
            reload()
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    // MARK: - Empty state

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("Pick a note from the list")
                .font(.headline).foregroundStyle(.secondary)
            Text("Or press ⌘N to start a new one.")
                .font(.subheadline).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private func reload() {
        do {
            notes = try appState.database.fetchObjects(typeId: typeId)
            // Sort by date desc, updated desc; cheap in memory.
            let dateKey = type?.calendarDateKey ?? "date"
            notes.sort { lhs, rhs in
                let ldate = (lhs.fields()[dateKey] as? String) ?? ""
                let rdate = (rhs.fields()[dateKey] as? String) ?? ""
                if ldate != rdate { return ldate > rdate }
                return lhs.updatedAt > rhs.updatedAt
            }
            if let id = selectedNoteId, !notes.contains(where: { $0.id == id }) {
                selectedNoteId = notes.first?.id
            } else if selectedNoteId == nil {
                selectedNoteId = notes.first?.id
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func createNote() {
        guard let t = type else { return }
        let today = ISO8601DateFormatter().string(from: Date())
        let isoDay = String(today.prefix(10)) // YYYY-MM-DD
        let fields: [String: Any] = [
            primaryKey: "",
            (t.calendarDateKey ?? "date"): isoDay
        ]
        do {
            let created = try ObjectEngine.create(typeId: typeId, fields: fields)
            reload()
            selectedNoteId = created.id
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteNote(_ note: ObjectRecord) {
        do {
            try ObjectEngine.delete(id: note.id)
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
