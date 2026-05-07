import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AttachmentsTab: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Attachments").font(.headline)
                Spacer()
                Button { addAttachment() } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
            }
            if app.attachmentsMeta.isEmpty {
                Text("No attachments yet. Files are stored as BLOBs inside the database with MD5 / SHA1 / SHA256 hashes; SHA1 is verified on each access.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(app.attachmentsMeta, id: \.id) { meta in
                    AttachmentRow(meta: meta)
                    Divider()
                }
            }
        }
    }

    private func addAttachment() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                do { try app.addAttachment(fileURL: url) }
                catch { app.errorMessage = error.localizedDescription }
            }
        }
    }
}

private struct AttachmentRow: View {
    let meta: (id: String, filename: String, sizeBytes: Int64, mimeType: String, sha1: String, lastVerifyOk: Bool)
    @EnvironmentObject var app: AppState
    @State private var lastWarning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: meta.lastVerifyOk ? "doc.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(meta.lastVerifyOk ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                Text(meta.filename).font(.body.weight(.medium))
                Spacer()
                Text(byteCount(meta.sizeBytes)).font(.caption).foregroundStyle(.secondary)
                Button("Open") { open() }
                Button("Save As…") { saveAs() }
                Button(role: .destructive) {
                    try? app.deleteAttachment(id: meta.id)
                } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                Text("SHA1 \(meta.sha1)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                if !meta.lastVerifyOk {
                    Text("⚠️ Hash mismatch on last verify")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
            if let w = lastWarning {
                Text(w).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private func open() {
        do {
            let r = try app.openAttachment(id: meta.id)
            if !r.verified {
                lastWarning = "SHA1 hash mismatch — file may be corrupted."
            } else {
                lastWarning = nil
            }
            NSWorkspace.shared.open(r.url)
        } catch { app.errorMessage = error.localizedDescription }
    }

    private func saveAs() {
        do {
            let r = try app.openAttachment(id: meta.id)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = meta.filename
            if panel.runModal() == .OK, let dest = panel.url {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: r.url, to: dest)
            }
        } catch { app.errorMessage = error.localizedDescription }
    }

    private func byteCount(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
