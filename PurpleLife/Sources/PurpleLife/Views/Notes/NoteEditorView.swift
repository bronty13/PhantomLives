import AppKit
import SwiftUI

/// Right pane of the Notes workspace — title + date + WYSIWYG body
/// editor with autosave. Mirrors PurpleTracker's `NoteEditorView`
/// (autosave on debounce + on view dismiss + on note-id change) but
/// goes through `ObjectEngine.update` rather than a dedicated service.
struct NoteEditorView: View {
    @EnvironmentObject private var appState: AppState
    let note: ObjectRecord
    let type: ObjectType
    let onChanged: () -> Void

    @State private var title: String = ""
    @State private var noteDate: Date = Date()
    @State private var attributed = NSAttributedString()
    @State private var sizeError: String?

    @State private var dirty: Bool = false
    @State private var saveWork: DispatchWorkItem?
    @State private var loadedId: String = ""
    @State private var saveError: String?

    // Snapshots of the values written by `loadIfNeeded`. Used by
    // `markDirty` and `saveNow` to distinguish real user edits from
    // SwiftUI's async `.onChange` firings triggered by the load-time
    // assignments. Without this guard, every note view triggers an
    // unnecessary 1.2s-debounced autosave whose only effect is a
    // round-trip ObjectEngine.update + sync push + undo registration
    // for content that didn't actually change.
    @State private var loadedTitle: String = ""
    @State private var loadedDate: Date = .distantPast
    @State private var loadedAttributed: NSAttributedString = NSAttributedString()

    private var primaryKey: String { type.primaryFieldKey ?? "title" }
    private var dateKey: String   { type.calendarDateKey ?? "date" }
    private var categoryKey: String? {
        type.fields.first(where: { $0.kind == .select })?.key
    }
    private var bodyKey: String {
        type.fields.first(where: { $0.kind == .richText })?.key ?? "body"
    }

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
            }
            .padding()

            Divider()

            RichTextEditor(attributed: $attributed)
                .onChange(of: attributed) { _, _ in markDirty() }
                .padding(.horizontal, 8).padding(.bottom, 8)

            if let sizeError {
                Text(sizeError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal).padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal).padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { loadIfNeeded() }
        .onChange(of: note.id) { _, _ in
            // Switching notes: flush pending save first so we don't lose
            // edits.
            saveNow()
            loadIfNeeded()
        }
        .onDisappear { saveNow() }
    }

    private func loadIfNeeded() {
        guard loadedId != note.id else { return }
        loadedId = note.id

        let fields = note.fields()
        title = (fields[primaryKey] as? String) ?? ""
        if let s = fields[dateKey] as? String,
           let d = ISO8601DateFormatter.parseDay(s) {
            noteDate = d
        } else {
            noteDate = Date()
        }
        if let dict = fields[bodyKey] as? [String: Any] {
            let value = RichTextValue.from(jsonDictionary: dict)
            let decoded = NSAttributedString.fromRTFData(value.rtf)
            if decoded.length == 0 && !value.plain.isEmpty {
                // Plain-only body (no RTF mirror) — happens for imported
                // / sample / migrated data that lacks a real RTF blob.
                // Materialize from the plain string so the editor
                // shows the content; the next save upgrades the
                // on-disk representation to rtf + plain.
                //
                // **MUST set explicit foregroundColor + font.** Without
                // attributes, NSTextView renders the string in its
                // default text color — black — invisible against the
                // dark-mode editor background. The two attributes
                // mirror the editor's own `clearFormatting` defaults
                // so a plain-text-recovered note renders identically
                // to a freshly-typed one.
                let defaultAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.labelColor
                ]
                attributed = NSAttributedString(string: value.plain, attributes: defaultAttrs)
            } else {
                attributed = decoded
            }
        } else {
            attributed = NSAttributedString()
        }
        // Capture the loaded values for the noop-edit guard in
        // markDirty / saveNow. MUST come AFTER all the assignments
        // above so the snapshot matches what SwiftUI will see when
        // it fires the load-induced .onChange handlers.
        loadedTitle = title
        loadedDate = noteDate
        loadedAttributed = attributed

        dirty = false
        saveError = nil
        sizeError = nil
    }

    /// Have any of the editable values diverged from the snapshot
    /// captured at load? When SwiftUI fires `.onChange` handlers for
    /// the assignments inside `loadIfNeeded` (which happens async on
    /// the next body re-eval), the current values still match what
    /// we just loaded; this returns `false` and `markDirty` bails.
    /// When the user actually types, the textview's textDidChange
    /// writes back a different attributed string (or title/date
    /// diverges), this returns `true` and the autosave proceeds.
    private var hasUnsavedEdits: Bool {
        if title != loadedTitle { return true }
        if noteDate != loadedDate { return true }
        if !attributed.isEqual(to: loadedAttributed) { return true }
        return false
    }

    private func markDirty() {
        guard loadedId == note.id else { return }
        // Suppress load-induced .onChange firings: if the current
        // values match the loaded snapshot, this isn't a real edit.
        guard hasUnsavedEdits else { return }
        dirty = true
        // Debounced autosave (1.2s after last edit).
        saveWork?.cancel()
        let work = DispatchWorkItem { saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func saveNow() {
        guard dirty, loadedId == note.id else { return }

        // Read the live NSTextView storage to pick up paste-inserted
        // attachments — same approach PurpleTracker uses (mirrors
        // RichTextField's writeBack trick).
        let live: NSAttributedString
        if let tv = RichTextRegistry.shared.firstResponderTextView(),
           let storage = tv.textStorage {
            live = NSAttributedString(attributedString: storage)
        } else {
            live = attributed
        }

        // Belt-and-suspenders against the same load-induced race:
        // even if `dirty` got set, double-check that the live state
        // actually differs from the loaded snapshot before writing.
        // This protects against any future code path that flips
        // `dirty` without going through `markDirty`'s guard.
        if title == loadedTitle,
           noteDate == loadedDate,
           live.isEqual(to: loadedAttributed) {
            dirty = false
            return
        }

        let rtf = live.toRTFData() ?? Data()
        if !RichTextLimits.fits(rtf) {
            sizeError = "Note too large to sync (\(rtf.count.formatted()) bytes; limit \(RichTextLimits.maxBlobBytes.formatted())). Reduce images and save again."
            return
        }
        sizeError = nil

        let body = RichTextValue(rtf: rtf, plain: live.string).jsonDictionary
        let dayString: String = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: noteDate)
        }()

        var patch: [String: Any] = [
            primaryKey: title,
            dateKey: dayString,
            bodyKey: body
        ]
        // Preserve any category field value the user set elsewhere — it
        // isn't editable in this view but undo + cross-mac edits could
        // touch it.
        if let catKey = categoryKey, let v = note.fields()[catKey] {
            patch[catKey] = v
        }

        do {
            _ = try ObjectEngine.update(note, fields: patch)
            dirty = false
            saveError = nil
            onChanged()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
