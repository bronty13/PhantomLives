import SwiftUI

/// Structured-notes panel for a single clip.
///
/// Shows the chronological list of `ClipNote` rows (operator + timestamp +
/// body), an inline composer at the top, and per-row Edit / Delete actions.
/// Mirrors the PurpleTracker NotesTab pattern. The legacy `clip.notes` blob
/// is intentionally not surfaced here — it's rendered in a separate
/// disclosure inside `ClipEditView` so structured and free-text history
/// stay distinguishable.
struct ClipNotesPanel: View {
    let clipId: String
    @EnvironmentObject private var appState: AppState

    @State private var notes: [ClipNote] = []
    @State private var newBody: String = ""
    @State private var addError: String? = nil
    @State private var editingId: Int64? = nil
    @State private var editingDraft: String = ""
    @State private var pendingDeleteId: Int64? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            composer
            EdHairline(color: EdColor.ink(0.18))
            if notes.isEmpty {
                Text("No notes yet.")
                    .font(EdFont.serif(15, weight: .light, italic: true))
                    .foregroundStyle(EdColor.ink(0.5))
                    .padding(.vertical, 8)
            } else {
                ForEach(notes) { n in
                    noteRow(n)
                    EdHairline(color: EdColor.ink(0.1))
                }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: clipId) { _, _ in reload() }
        .alert("Delete this note?",
               isPresented: Binding(get: { pendingDeleteId != nil },
                                    set: { if !$0 { pendingDeleteId = nil } })) {
            Button("Cancel", role: .cancel) { pendingDeleteId = nil }
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteId {
                    try? appState.deleteClipNote(id: id)
                    reload()
                }
                pendingDeleteId = nil
            }
        } message: {
            Text("Notes are deleted permanently. The clip's automatic markers (status changes, posting, audit) live in a separate timeline and aren't affected.")
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                EdEyebrow(text: "Add a note", withRule: false)
                Spacer()
                Text("AS \(authorLabel)")
                    .font(EdFont.mono(10.5))
                    .tracking(0.84)
                    .foregroundStyle(EdColor.ink(0.55))
            }
            TextEditor(text: $newBody)
                .font(EdFont.sans(13.5))
                .frame(minHeight: 70, maxHeight: 160)
                .padding(6)
                .overlay(Rectangle().strokeBorder(EdColor.ink(0.25), lineWidth: 1))
            HStack {
                if let err = addError {
                    Text(err)
                        .font(EdFont.mono(10.5))
                        .foregroundStyle(.red)
                }
                Spacer()
                Button {
                    save()
                } label: { Text("ADD NOTE") }
                .buttonStyle(EdInkPillButtonStyle())
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(trimmedNew.isEmpty)
                .help("⌘↩ to save")
            }
        }
    }

    private var trimmedNew: String {
        newBody.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var authorLabel: String {
        let name = appState.settings.operatorName.trimmingCharacters(in: .whitespaces)
        return (name.isEmpty ? "ME" : name).uppercased()
    }

    // MARK: - Row

    private func noteRow(_ note: ClipNote) -> some View {
        let editing = editingId == note.id

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatTimestamp(note.createdAt))
                    .font(EdFont.mono(10.5, weight: .semibold))
                    .tracking(0.84)
                    .foregroundStyle(EdColor.ink)
                if !note.operatorName.isEmpty {
                    Text("· \(note.operatorName.uppercased())")
                        .font(EdFont.mono(10.5))
                        .tracking(0.6)
                        .foregroundStyle(EdColor.ink(0.55))
                }
                if note.updatedAt > note.createdAt {
                    Text("· edited \(formatTimestamp(note.updatedAt))")
                        .font(EdFont.mono(10))
                        .foregroundStyle(EdColor.ink(0.45))
                }
                Spacer()
                if editing {
                    Button { commitEdit(note) } label: { Text("SAVE") }
                        .buttonStyle(EdGhostButtonStyle())
                        .disabled(editingDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button { cancelEdit() } label: { Text("CANCEL") }
                        .buttonStyle(EdGhostButtonStyle())
                } else {
                    Button { beginEdit(note) } label: { Text("EDIT") }
                        .buttonStyle(EdGhostButtonStyle())
                    Button(role: .destructive) {
                        pendingDeleteId = note.id
                    } label: { Text("DELETE") }
                        .buttonStyle(EdGhostButtonStyle())
                }
            }
            if editing {
                TextEditor(text: $editingDraft)
                    .font(EdFont.sans(13.5))
                    .frame(minHeight: 70, maxHeight: 200)
                    .padding(6)
                    .overlay(Rectangle().strokeBorder(EdColor.ink(0.25), lineWidth: 1))
            } else {
                Text(note.body)
                    .font(EdFont.sans(13.5))
                    .foregroundStyle(EdColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func reload() {
        notes = appState.fetchClipNotes(clipId: clipId)
    }

    private func save() {
        let body = trimmedNew
        guard !body.isEmpty else { return }
        do {
            _ = try appState.addClipNote(clipId: clipId, body: body)
            newBody = ""
            addError = nil
            reload()
        } catch {
            addError = error.localizedDescription
        }
    }

    private func beginEdit(_ note: ClipNote) {
        editingId = note.id
        editingDraft = note.body
    }

    private func cancelEdit() {
        editingId = nil
        editingDraft = ""
    }

    private func commitEdit(_ note: ClipNote) {
        let trimmed = editingDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var copy = note
        copy.body = trimmed
        try? appState.updateClipNote(copy)
        cancelEdit()
        reload()
    }

    // MARK: - Formatting

    /// `2026-05-08T13:42:11Z` → `2026-05-08 · 13:42` (always local TZ).
    private func formatTimestamp(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        guard let d = parser.date(from: iso) ?? Self.fallbackParser.date(from: iso) else {
            return iso
        }
        return Self.displayFormatter.string(from: d)
    }

    private static let fallbackParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd · HH:mm"
        return f
    }()
}
