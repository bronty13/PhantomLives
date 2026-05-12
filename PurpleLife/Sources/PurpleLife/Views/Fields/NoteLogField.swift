import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Field renderer for `.noteLog` — a timestamped activity log. Top:
/// rich-text input + paperclip-or-drop attach + Post button. Below: the
/// list of committed entries, newest first, each with its own edit /
/// delete affordances and per-entry attachment chips (open / save).
struct NoteLogField: View {
    let fieldKey: String
    let parentObjectId: String
    @Binding var fieldsBuffer: [String: Any]

    @State private var draftAttributed = NSAttributedString()
    @State private var pendingAttachments: [URL] = []
    @State private var dropTargeted = false
    /// IDs of entries currently being hovered as a drop target. Set as
    /// rows fire their `isTargeted` callbacks; consulted by the
    /// field-level overlay so it suppresses itself when a child row is
    /// also showing its own targeted state (avoids two blue borders
    /// nested inside each other).
    @State private var dropTargetedEntryIds: Set<String> = []

    @State private var editingEntryId: String?
    @State private var editingAttributed = NSAttributedString()

    @State private var error: String?

    private var value: NoteLogValue {
        guard let dict = fieldsBuffer[fieldKey] as? [String: Any] else { return .empty }
        return NoteLogValue.from(jsonDictionary: dict)
    }

    private var sortedEntries: [NoteLogEntry] {
        value.entries.sorted(by: { $0.createdAt > $1.createdAt })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            inputArea
            if !sortedEntries.isEmpty {
                Divider().padding(.vertical, 2)
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(sortedEntries) { entry in
                        entryRow(entry)
                        if entry.id != sortedEntries.last?.id {
                            Divider().opacity(0.5)
                        }
                    }
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        // Drop destination spans the whole field surface (input + list).
        // URLs dropped here become pending attachments on the *next*
        // entry the user posts — same path as the paperclip picker, so
        // the user can mix-and-match without surprise. Drops that land
        // ON an existing entry are caught by that entry's own
        // destination (defined inside `entryRow`); SwiftUI routes the
        // drop to the innermost matching destination, so the
        // pending-path here only fires for drops on the input area or
        // the gaps between entries.
        .dropDestination(for: URL.self) { urls, _ in
            attachFiles(urls, toEntryId: nil)
            return !urls.isEmpty
        } isTargeted: { targeted in
            dropTargeted = targeted
        }
        .overlay(dropOverlay)
    }

    // MARK: - Input area

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            RichTextEditor(
                attributed: $draftAttributed,
                onAttachmentExtracted: { image, data, filename in
                    handlePastedImage(image, data: data, filename: filename)
                }
            )
            .frame(minHeight: 80, maxHeight: 180)
            HStack(spacing: 8) {
                Button {
                    pickAttachments()
                } label: {
                    Label("Attach files…", systemImage: "paperclip")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("⌘↵")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                Button("Post") { commitDraft() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(draftIsEmpty)
            }
            if !pendingAttachments.isEmpty {
                pendingChips
            }
        }
    }

    private var draftIsEmpty: Bool {
        draftAttributed.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && pendingAttachments.isEmpty
    }

    private var pendingChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(pendingAttachments, id: \.self) { url in
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip").imageScale(.small)
                        Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Button {
                            pendingAttachments.removeAll { $0 == url }
                        } label: {
                            Image(systemName: "xmark.circle.fill").imageScale(.small)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var dropOverlay: some View {
        // Field-level overlay only when the drag is over the field
        // surface AND not currently over a specific entry row. The
        // row-level overlay (see entryRow) handles the latter case
        // with a tighter highlight.
        if dropTargeted && dropTargetedEntryIds.isEmpty {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .background(Color.accentColor.opacity(0.08))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func entryDropOverlay(for entryId: String) -> some View {
        if dropTargetedEntryIds.contains(entryId) {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .background(Color.accentColor.opacity(0.10))
                .allowsHitTesting(false)
        }
    }

    // MARK: - Entry row

    @ViewBuilder
    private func entryRow(_ entry: NoteLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(formatTimestamp(entry.createdAt))
                    .font(.caption).foregroundStyle(.secondary)
                if entry.updatedAt != entry.createdAt {
                    Text("· edited").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Menu {
                    Button(editingEntryId == entry.id ? "Cancel edit" : "Edit") {
                        toggleEdit(for: entry)
                    }
                    Button("Delete", role: .destructive) {
                        deleteEntry(entry)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            if editingEntryId == entry.id {
                RichTextEditor(
                    attributed: $editingAttributed,
                    onAttachmentExtracted: { image, data, filename in
                        handlePastedImage(image, data: data, filename: filename)
                    }
                )
                .frame(minHeight: 80, maxHeight: 180)
                HStack {
                    Spacer()
                    Button("Cancel") { editingEntryId = nil }
                    Button("Save") { commitEdit(for: entry) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            } else {
                RichTextDisplay(attributed: NSAttributedString.fromRTFData(entry.rtfData))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !entry.attachments.isEmpty {
                attachmentRow(entry.attachments)
            }
        }
        // Per-entry drop destination — files dropped directly on this
        // entry's bounding box upload immediately and append to THIS
        // entry's attachments (rather than the pending pool for the
        // next-posted entry). SwiftUI routes drops to the innermost
        // matching destination, so this catches drops on the row body
        // before the field-level destination above sees them.
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            attachFiles(urls, toEntryId: entry.id)
            return !urls.isEmpty
        } isTargeted: { targeted in
            if targeted {
                dropTargetedEntryIds.insert(entry.id)
            } else {
                dropTargetedEntryIds.remove(entry.id)
            }
        }
        .overlay(entryDropOverlay(for: entry.id))
    }

    @ViewBuilder
    private func attachmentRow(_ refs: [NoteLogAttachmentRef]) -> some View {
        FlowAttachmentRow(refs: refs,
                          onOpen: openAttachment,
                          onSave: downloadAttachment)
    }

    // MARK: - Commit / edit / delete

    private func commitDraft() {
        let plain = draftAttributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty || !pendingAttachments.isEmpty else { return }

        let rtf = draftAttributed.toRTFData() ?? Data()
        guard NoteLogLimits.fits(rtf) else {
            error = "Entry is too large to sync — limit is \(NoteLogLimits.maxEntryRTFBytes.formatted()) bytes."
            return
        }

        var refs: [NoteLogAttachmentRef] = []
        for url in pendingAttachments {
            do {
                let row = try AttachmentService.add(from: url,
                                                     parentObjectId: parentObjectId,
                                                     fieldKey: fieldKey)
                refs.append(NoteLogAttachmentRef(
                    id: row.id,
                    sha256: row.sha256,
                    filename: row.filename,
                    mimeType: row.mimeType,
                    sizeBytes: row.sizeBytes
                ))
            } catch {
                self.error = "Attachment failed: \(error.localizedDescription)"
                return
            }
        }

        var current = value
        current.entries.append(NoteLogEntry.new(rtf: rtf, plain: plain, attachments: refs))
        fieldsBuffer[fieldKey] = current.jsonDictionary

        draftAttributed = NSAttributedString()
        pendingAttachments.removeAll()
        error = nil
    }

    private func toggleEdit(for entry: NoteLogEntry) {
        if editingEntryId == entry.id {
            editingEntryId = nil
        } else {
            editingEntryId = entry.id
            editingAttributed = NSAttributedString.fromRTFData(entry.rtfData)
        }
    }

    private func commitEdit(for entry: NoteLogEntry) {
        let rtf = editingAttributed.toRTFData() ?? Data()
        guard NoteLogLimits.fits(rtf) else {
            error = "Edited entry is too large — limit is \(NoteLogLimits.maxEntryRTFBytes.formatted()) bytes."
            return
        }
        var current = value
        guard let idx = current.entries.firstIndex(where: { $0.id == entry.id }) else { return }
        current.entries[idx].rtf = rtf.base64EncodedString()
        current.entries[idx].plain = editingAttributed.string
        current.entries[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
        fieldsBuffer[fieldKey] = current.jsonDictionary
        editingEntryId = nil
        error = nil
    }

    private func deleteEntry(_ entry: NoteLogEntry) {
        // Ref-counted cleanup: delete each attachment row. The file on
        // disk is only pruned when no other row references the same
        // sha256 (handled inside AttachmentService.deleteRow).
        for ref in entry.attachments {
            try? AttachmentService.deleteRow(id: ref.id)
        }
        var current = value
        current.entries.removeAll { $0.id == entry.id }
        fieldsBuffer[fieldKey] = current.jsonDictionary
        if editingEntryId == entry.id { editingEntryId = nil }
    }

    // MARK: - Drop routing

    /// Attach file URLs either to a specific entry (drag-drop on a row)
    /// or to the pending-attachments queue for the next-posted entry
    /// (drag-drop on the field area, paperclip picker, paste-image
    /// extraction in the input editor). The per-entry path uploads
    /// immediately and bumps `updatedAt`; the pending path just buffers
    /// URLs and lets `commitDraft` do the upload on Post.
    private func attachFiles(_ urls: [URL], toEntryId entryId: String?) {
        guard !urls.isEmpty else { return }
        guard let entryId else {
            pendingAttachments.append(contentsOf: urls)
            error = nil
            return
        }

        var refs: [NoteLogAttachmentRef] = []
        for url in urls {
            do {
                let row = try AttachmentService.add(
                    from: url,
                    parentObjectId: parentObjectId,
                    fieldKey: fieldKey
                )
                refs.append(NoteLogAttachmentRef(
                    id: row.id,
                    sha256: row.sha256,
                    filename: row.filename,
                    mimeType: row.mimeType,
                    sizeBytes: row.sizeBytes
                ))
            } catch {
                self.error = "Attachment failed: \(error.localizedDescription)"
                return
            }
        }

        var current = value
        guard let idx = current.entries.firstIndex(where: { $0.id == entryId }) else { return }
        current.entries[idx].attachments.append(contentsOf: refs)
        current.entries[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
        fieldsBuffer[fieldKey] = current.jsonDictionary
        error = nil
    }

    // MARK: - Paste-image extraction

    /// Called when `RichTextEditor` reports a fresh image attachment in
    /// its storage (typically a paste). Writes the bytes to a temp
    /// file, then either:
    ///   * Edit mode → upload immediately + attach to the entry being
    ///     edited (the user's mental model is "I'm adding to THIS
    ///     entry"; making it pending would be weirdly indirect).
    ///   * Input area → join the pending-attachments queue for the
    ///     next-posted entry. Same path as paperclip + drag-drop.
    ///
    /// The temp file is cleaned up after `AttachmentService.add` copies
    /// the bytes into the content-addressed store (edit-mode path).
    /// For the pending path it lingers until commit — when
    /// `commitDraft` calls `AttachmentService.add` on each URL — and
    /// would in any case eventually be reaped by macOS from
    /// `NSTemporaryDirectory`.
    private func handlePastedImage(_ image: NSImage, data: Data, filename: String?) {
        // Pick a filename. Prefer what the source provided (paste from
        // a real file carries the original name); fall back to a
        // sensible default. Always add a UUID suffix so concurrent
        // pastes can't collide on the same temp path.
        let providedExt = filename.flatMap { ($0 as NSString).pathExtension }
        let ext: String = (providedExt?.isEmpty == false) ? providedExt! : "png"
        let providedBase = filename.flatMap { ($0 as NSString).deletingPathExtension }
        let base: String = (providedBase?.isEmpty == false) ? providedBase! : "pasted-image"
        let unique = "\(base)-\(UUID().uuidString.prefix(8)).\(ext)"

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(unique)
        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            self.error = "Couldn't capture pasted image: \(error.localizedDescription)"
            return
        }

        if let editingId = editingEntryId {
            do {
                let row = try AttachmentService.add(
                    from: tempURL,
                    parentObjectId: parentObjectId,
                    fieldKey: fieldKey
                )
                var current = value
                guard let idx = current.entries.firstIndex(where: { $0.id == editingId }) else {
                    try? FileManager.default.removeItem(at: tempURL)
                    return
                }
                current.entries[idx].attachments.append(NoteLogAttachmentRef(
                    id: row.id,
                    sha256: row.sha256,
                    filename: row.filename,
                    mimeType: row.mimeType,
                    sizeBytes: row.sizeBytes
                ))
                current.entries[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
                fieldsBuffer[fieldKey] = current.jsonDictionary
                try? FileManager.default.removeItem(at: tempURL)
                error = nil
            } catch {
                self.error = "Attachment failed: \(error.localizedDescription)"
            }
        } else {
            pendingAttachments.append(tempURL)
            error = nil
        }
    }

    // MARK: - Attachment pick / open / save

    private func pickAttachments() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.title = "Attach files"
        if panel.runModal() == .OK {
            pendingAttachments.append(contentsOf: panel.urls)
        }
    }

    private func openAttachment(_ ref: NoteLogAttachmentRef) {
        guard let data = try? AttachmentService.read(sha256: ref.sha256) else {
            error = "Couldn't decrypt attachment for opening."
            return
        }
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurpleLife-NoteLog", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempURL = tempDir.appendingPathComponent(ref.filename)
        do {
            try data.write(to: tempURL, options: .atomic)
            NSWorkspace.shared.open(tempURL)
        } catch {
            self.error = "Couldn't write temp file: \(error.localizedDescription)"
        }
    }

    private func downloadAttachment(_ ref: NoteLogAttachmentRef) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ref.filename
        if panel.runModal() == .OK, let dest = panel.url {
            guard let data = try? AttachmentService.read(sha256: ref.sha256) else {
                error = "Couldn't decrypt attachment for saving."
                return
            }
            do {
                try data.write(to: dest, options: .atomic)
            } catch {
                self.error = "Couldn't save: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Helpers

    private func formatTimestamp(_ iso: String) -> String {
        guard let d = ISO8601DateFormatter().date(from: iso) else { return iso }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }
}

// MARK: - Attachment chips (wrapping row)

/// Horizontal-wrapping row of attachment chips. Each chip shows the
/// filename plus Open / Save buttons. Built on `Layout` so it adapts
/// to the available width without forcing a horizontal scroll.
private struct FlowAttachmentRow: View {
    let refs: [NoteLogAttachmentRef]
    let onOpen: (NoteLogAttachmentRef) -> Void
    let onSave: (NoteLogAttachmentRef) -> Void

    var body: some View {
        WrappingHStack(items: refs, spacing: 6, lineSpacing: 6) { ref in
            chip(ref)
        }
    }

    @ViewBuilder
    private func chip(_ ref: NoteLogAttachmentRef) -> some View {
        HStack(spacing: 4) {
            Image(systemName: iconName(for: ref))
                .imageScale(.small)
                .foregroundStyle(.secondary)
            Text(ref.filename)
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                onOpen(ref)
            } label: {
                Text("Open").underline()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tint)
            Text("·").foregroundStyle(.tertiary)
            Button {
                onSave(ref)
            } label: {
                Text("Save").underline()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tint)
        }
        .font(.caption)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func iconName(for ref: NoteLogAttachmentRef) -> String {
        if ref.mimeType.hasPrefix("image/")          { return "photo" }
        if ref.mimeType.hasPrefix("video/")          { return "film" }
        if ref.mimeType.hasPrefix("audio/")          { return "music.note" }
        if ref.mimeType == "application/pdf"         { return "doc.richtext" }
        if ref.mimeType.contains("zip") || ref.mimeType.contains("compressed") { return "doc.zipper" }
        return "doc"
    }
}

/// Generic wrapping HStack — items flow left-to-right and wrap when
/// they hit the container's trailing edge. Same shape as the helper
/// used in `Detail.swift` for multi-select chips, repeated here so
/// the noteLog field doesn't reach into Detail's internals.
private struct WrappingHStack<Item: Hashable, Content: View>: View {
    let items: [Item]
    var spacing: CGFloat
    var lineSpacing: CGFloat
    let content: (Item) -> Content

    var body: some View {
        GeometryReader { geo in
            self.layout(items: items, containerWidth: geo.size.width)
        }
        .frame(minHeight: 24)
    }

    private func layout(items: [Item], containerWidth: CGFloat) -> some View {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                content(item)
                    .padding(.trailing, spacing)
                    .padding(.bottom, lineSpacing)
                    .alignmentGuide(.leading) { dim in
                        if x + dim.width > containerWidth {
                            x = 0
                            y -= lineHeight + lineSpacing
                            lineHeight = 0
                        }
                        let result = x
                        if item == items.last { x = 0 } else { x += dim.width + spacing }
                        lineHeight = max(lineHeight, dim.height)
                        return -result
                    }
                    .alignmentGuide(.top) { _ in y }
            }
        }
    }
}
