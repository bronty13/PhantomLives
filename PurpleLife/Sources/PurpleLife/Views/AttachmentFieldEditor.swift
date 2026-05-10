import SwiftUI
import UniformTypeIdentifiers

/// File picker for `.attachment` fields. Stores the sha256 of the file
/// in the field's value; the on-disk content lives at the
/// content-addressed path managed by `AttachmentService`.
///
/// Replacing an existing attachment: the previous row's content stays
/// on disk if any other ref shares the sha256; otherwise it's pruned
/// by `AttachmentService.deleteRow`. The user just sees the value
/// change to the new hash.
struct AttachmentFieldEditor: View {
    @EnvironmentObject private var appState: AppState

    /// Bound to the field's string value in `Detail.swift`'s
    /// `fieldsBuffer`. The string is the sha256 hex.
    @Binding var value: String

    let parentObjectId: String
    let fieldKey: String

    @State private var pickingFile = false
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            preview
            HStack {
                Button {
                    pickFile()
                } label: {
                    Label(value.isEmpty ? "Pick file…" : "Replace…", systemImage: "paperclip")
                }
                if !value.isEmpty {
                    Button(role: .destructive) {
                        clear()
                    } label: {
                        Label("Remove", systemImage: "xmark.circle")
                    }
                }
                Spacer()
            }
            if let loadError {
                Text(loadError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if value.isEmpty {
            HStack {
                Image(systemName: "paperclip")
                    .foregroundStyle(.tertiary)
                Text("No file attached.")
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .padding(12)
            .background(Color.secondary.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4])))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if let url = AttachmentService.fileURL(forSha256: value) {
            if let nsImage = NSImage(contentsOf: url) {
                HStack(alignment: .top, spacing: 10) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 220, maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                    metadata(url: url, nsImage: nsImage)
                }
            } else {
                fileFallback(url: url)
            }
        } else {
            // The field has a sha256 but the file isn't in our store —
            // maybe a sync arrived with a CKAsset we haven't downloaded
            // yet, or the row was pruned. Display the broken state
            // explicitly instead of silently rendering "no attachment".
            HStack {
                Image(systemName: "link.badge.questionmark")
                    .foregroundStyle(.orange)
                Text("Attachment not found locally (\(value.prefix(12))…)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
    }

    private func metadata(url: URL, nsImage: NSImage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(url.lastPathComponent)
                .font(.body.monospaced())
                .lineLimit(1)
            Text("\(Int(nsImage.size.width))×\(Int(nsImage.size.height))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int {
                Text(ByteCountFormatter().string(fromByteCount: Int64(size)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Reveal") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            .controlSize(.small)
        }
    }

    private func fileFallback(url: URL) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.body.monospaced())
                    .lineLimit(1)
                Text("Not previewable here · Reveal to open in Finder")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Reveal") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Actions

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                // Replace any existing attachment ref under this (parent, field)
                // first — content stays on disk if another row shares its sha256.
                try AttachmentService.clear(forParent: parentObjectId, fieldKey: fieldKey)
                let row = try AttachmentService.add(from: url, parentObjectId: parentObjectId, fieldKey: fieldKey)
                value = row.sha256
                loadError = nil
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    private func clear() {
        do {
            try AttachmentService.clear(forParent: parentObjectId, fieldKey: fieldKey)
            value = ""
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}
