import SwiftUI
import AppKit

/// WYSIWYG editor for a single `GenericNote`. The note's date and title are
/// edited inline; the body is a rich-text editor whose `NSAttributedString`
/// is round-tripped through RTF on save. Autosaves on blur, debounce, and
/// when SwiftUI sees the source note change identity.
struct NoteEditorView: View {
    @EnvironmentObject var app: AppState
    let note: GenericNote

    @State private var noteDate: Date = Date()
    @State private var title: String = ""
    @State private var body_: NSAttributedString = NSAttributedString()
    @State private var dirty: Bool = false
    @State private var saveWork: DispatchWorkItem?
    @State private var loadedId: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                DatePicker("", selection: $noteDate, displayedComponents: .date)
                    .labelsHidden()
                    .onChange(of: noteDate) { _, _ in markDirty() }
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .onChange(of: title) { _, _ in markDirty() }
                Text(dirty ? "Unsaved…" : "Saved")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    saveNow()
                } label: { Label("Save", systemImage: "tray.and.arrow.down") }
                    .keyboardShortcut("s", modifiers: .command)
                Button(role: .destructive) {
                    try? app.deleteGenericNote(id: note.id)
                } label: { Image(systemName: "trash") }
                    .help("Delete note")
            }
            .padding()
            Divider()
            RichTextEditor(attributed: $body_)
                .onChange(of: body_) { _, _ in markDirty() }
                .padding(.horizontal, 8).padding(.bottom, 8)
        }
        .onAppear { loadIfNeeded() }
        .onChange(of: note.id) { _, _ in
            // Switching notes: flush pending save first so we don't lose edits.
            saveNow()
            loadIfNeeded()
        }
        .onDisappear { saveNow() }
    }

    private func loadIfNeeded() {
        guard loadedId != note.id else { return }
        loadedId = note.id
        noteDate = note.noteDate
        title = note.title
        body_ = NSAttributedString.fromRTFData(note.bodyRtf)
        dirty = false
    }

    private func markDirty() {
        guard loadedId == note.id else { return }
        dirty = true
        // Debounced autosave (1.2s after last edit).
        saveWork?.cancel()
        let work = DispatchWorkItem { saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func saveNow() {
        guard dirty, loadedId == note.id else { return }
        var updated = note
        updated.noteDate = noteDate
        updated.title = title
        updated.bodyRtf = body_.toRTFData()
        updated.bodyPlain = body_.string
        do {
            try app.updateGenericNote(updated)
            dirty = false
        } catch {
            app.errorMessage = error.localizedDescription
        }
    }
}
