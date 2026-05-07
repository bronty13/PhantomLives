import SwiftUI
import UniformTypeIdentifiers

/// Reusable attachment grid + add-button + drag-drop drop zone. Embedded in
/// the case / event / person editor sheets. Refreshes on every appear and
/// after each add/delete; for editors that aren't yet persisted (e.g. the
/// brand-new event in the New Event sheet), pass a non-nil `parentId` only
/// after the parent has been saved at least once.
struct AttachmentList: View {
    let parent: AttachmentParent
    /// Optional so the editor can hide the list entirely until the parent
    /// row exists (we need a real `parentId` to attach to).
    let parentId: String?

    @State private var attachments: [Attachment] = []
    @State private var error: String?
    @State private var previewAttachment: Attachment?
    @State private var pendingDeleteId: String?
    @State private var isDropTargeted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Attachments")
                    .font(.headline)
                if !attachments.isEmpty {
                    Text("(\(attachments.count) · \(formatBytes(totalBytes)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    addFromPicker()
                } label: {
                    Label("Add file…", systemImage: "paperclip")
                }
                .disabled(parentId == nil)
            }

            if parentId == nil {
                Text("Save the record first, then add attachments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
            } else if attachments.isEmpty {
                dropZone(empty: true)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)],
                           spacing: 10) {
                    ForEach(attachments) { att in
                        AttachmentTile(attachment: att) {
                            previewAttachment = att
                        } onDelete: {
                            pendingDeleteId = att.id
                        } onSave: {
                            saveToDisk(att)
                        }
                    }
                }
                dropZone(empty: false)
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear { reload() }
        .onChange(of: parentId) { _, _ in reload() }
        .sheet(item: $previewAttachment) { att in
            AttachmentPreview(attachment: att) {
                previewAttachment = nil
            }
        }
        .alert("Delete attachment?",
               isPresented: Binding(get: { pendingDeleteId != nil },
                                     set: { if !$0 { pendingDeleteId = nil } })) {
            Button("Cancel", role: .cancel) { pendingDeleteId = nil }
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteId { deleteAttachment(id: id) }
                pendingDeleteId = nil
            }
        } message: {
            Text("The file will be removed from the database. This can't be undone (the next backup will not include it).")
        }
    }

    // MARK: - Drop zone

    private func dropZone(empty: Bool) -> some View {
        let label = empty
            ? "Drop files here or click **Add file…** above"
            : "Drop more files here…"
        return HStack {
            Image(systemName: "tray.and.arrow.down")
                .foregroundStyle(.secondary)
            Text(.init(label))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill((isDropTargeted ? Color.accentColor : Color.gray).opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    (isDropTargeted ? Color.accentColor : .secondary.opacity(0.4)),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private var totalBytes: Int64 {
        attachments.map(\.sizeBytes).reduce(0, +)
    }

    // MARK: - Side effects

    private func reload() {
        guard let parentId else {
            attachments = []
            return
        }
        do {
            attachments = try DatabaseService.shared.fetchAttachments(parentType: parent, parentId: parentId)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func addFromPicker() {
        guard let parentId else { return }
        let urls = AttachmentService.chooseFiles()
        for url in urls {
            addOne(url: url, parentId: parentId)
        }
        reload()
    }

    private func addOne(url: URL, parentId: String) {
        do {
            let pos = attachments.count
            _ = try AttachmentService.addAttachment(
                from: url, to: parent, parentId: parentId, position: pos
            )
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        guard let parentId else { return }
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    addOne(url: url, parentId: parentId)
                    reload()
                }
            }
        }
    }

    private func deleteAttachment(id: String) {
        do {
            try DatabaseService.shared.deleteAttachment(id: id)
            error = nil
            reload()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func saveToDisk(_ att: Attachment) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = att.filename
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try att.data.write(to: url, options: .atomic)
            } catch {
                self.error = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}

// MARK: - Tile

private struct AttachmentTile: View {
    let attachment: Attachment
    let onTap: () -> Void
    let onDelete: () -> Void
    let onSave: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    if let thumb = attachment.thumbnailData,
                       let img = NSImage(data: thumb) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: glyphName)
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.quaternary.opacity(0.4))
                    }
                }
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(.secondary.opacity(0.3), lineWidth: 0.5)
                )

                Text(attachment.filename)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(formatBytes(attachment.sizeBytes))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open Preview", action: onTap)
            Button("Save to Disk…", action: onSave)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var glyphName: String {
        if attachment.isImage { return "photo" }
        if attachment.isPDF { return "doc.fill" }
        return "doc"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}

// MARK: - Preview sheet

private struct AttachmentPreview: View {
    let attachment: Attachment
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: glyph)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.filename).font(.headline.monospaced())
                    Text(attachment.mimeType).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", role: .cancel, action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 640, idealWidth: 760, maxWidth: 1100,
               minHeight: 480, idealHeight: 600, maxHeight: 900)
    }

    @ViewBuilder
    private var content: some View {
        if attachment.isImage, let nsImage = NSImage(data: attachment.data) {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .padding(20)
            }
        } else if attachment.isPDF {
            // PDFKit lives in its own framework; the View wrapper avoids
            // pulling that import unless we render a PDF.
            PDFAttachmentView(data: attachment.data)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No inline preview available for this file type.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var glyph: String {
        if attachment.isImage { return "photo" }
        if attachment.isPDF { return "doc.fill" }
        return "doc"
    }
}
