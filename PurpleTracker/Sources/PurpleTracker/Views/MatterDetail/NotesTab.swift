import SwiftUI

struct NotesTab: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var newBody: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes Log").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text("New entry").font(.caption).foregroundStyle(.secondary)
                SpellCheckTextEditor(
                    text: $newBody,
                    autocorrectEnabled: settingsStore.settings.autocorrectEnabled
                )
                .frame(minHeight: 100)
                HStack {
                    Spacer()
                    Button("Add Note") {
                        let body = newBody.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !body.isEmpty else { return }
                        try? app.addNote(body: body)
                        newBody = ""
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(newBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Divider()
            ForEach(app.notes) { n in
                NoteRow(note: n)
                Divider()
            }
            if app.notes.isEmpty {
                Text("No notes yet.").foregroundStyle(.secondary).padding(.top)
            }
        }
    }
}

private struct NoteRow: View {
    let note: Note
    @EnvironmentObject var app: AppState
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var editing = false
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if note.updatedAt > note.createdAt {
                    Text("(edited \(note.updatedAt.formatted(date: .abbreviated, time: .shortened)))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if editing {
                    Button("Save") {
                        var n = note; n.bodyMd = draft
                        try? app.updateNote(n)
                        editing = false
                    }
                    Button("Cancel") { editing = false }
                } else {
                    Button { draft = note.bodyMd; editing = true } label: { Image(systemName: "pencil") }
                        .buttonStyle(.plain)
                    Button(role: .destructive) { try? app.deleteNote(id: note.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }
            if editing {
                SpellCheckTextEditor(
                    text: $draft,
                    autocorrectEnabled: settingsStore.settings.autocorrectEnabled
                )
                .frame(minHeight: 100)
            } else {
                Text(LocalizedStringKey(note.bodyMd))
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }
}
