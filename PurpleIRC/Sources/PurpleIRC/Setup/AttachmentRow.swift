import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Attachment row

/// One row in the AddressEntryEditor's "Attachments" section. Shows
/// the file icon (resolved from the MIME type via UTType), filename,
/// and a human-readable size, plus three affordances: Open (hand
/// off to the OS via NSWorkspace), Reveal (in Finder), Remove
/// (drops both the inline ref and the blob-store payload).
struct AttachmentRow: View {
    let ref: BlobStore.AttachmentRef
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void

    private var iconName: String {
        // Map common MIME prefixes to SF Symbols. Anything not on
        // this list falls through to a generic doc icon — keeps the
        // visual cue useful without exhaustive enumeration.
        let mime = ref.contentType.lowercased()
        if mime.hasPrefix("image/")             { return "photo" }
        if mime.hasPrefix("video/")             { return "film" }
        if mime.hasPrefix("audio/")             { return "music.note" }
        if mime.hasPrefix("text/")              { return "doc.text" }
        if mime.contains("pdf")                 { return "doc.richtext" }
        if mime.contains("zip") || mime.contains("compressed") { return "archivebox" }
        if mime.contains("json") || mime.contains("xml") { return "curlybraces" }
        return "doc"
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(ref.sizeBytes),
                                  countStyle: .file)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(ref.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(ref.contentType) • \(formattedSize)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                onOpen()
            } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .help("Open with default app")
            .buttonStyle(.borderless)
            Button {
                onReveal()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Reveal in Finder")
            .buttonStyle(.borderless)
            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "trash")
            }
            .help("Remove attachment (deletes blob)")
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

