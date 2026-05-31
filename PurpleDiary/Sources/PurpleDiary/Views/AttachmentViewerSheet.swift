import SwiftUI
import AVKit
import AppKit
import UniformTypeIdentifiers

/// Full-size viewer for one attachment: a fit-to-window image for photos, or an
/// AVKit player for video. The full `data` BLOB is loaded once on appear; for
/// video it's written to a temp file (AVPlayer needs a URL) that's cleaned up on
/// dismiss. A "Save a Copy…" action lets the user pull the original bytes back
/// out to disk.
struct AttachmentViewerSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let attachmentId: String

    @State private var attachment: Attachment?
    @State private var tempVideoURL: URL?
    @State private var player: AVPlayer?
    @State private var loadFailed = false

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.04))
            Divider()
            footer
        }
        .frame(width: 760, height: 620)
        .task { await load() }
        .onDisappear(perform: cleanup)
    }

    @ViewBuilder
    private var content: some View {
        if let attachment {
            if attachment.isVideo {
                if let player {
                    VideoPlayer(player: player)
                        .onAppear { player.play() }
                } else {
                    placeholder("video.slash", "Couldn’t play this video.")
                }
            } else if let img = NSImage(data: attachment.data) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                placeholder("photo", "Couldn’t display this photo.")
            }
        } else if loadFailed {
            placeholder("exclamationmark.triangle", "This attachment is missing.")
        } else {
            ProgressView().controlSize(.large)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment?.filename ?? "Attachment")
                    .font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                if let a = attachment {
                    Text(captionLine(a)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if attachment != nil {
                Button("Save a Copy…", action: saveCopy)
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    private func placeholder(_ symbol: String, _ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(message).font(.headline).foregroundStyle(.secondary)
        }
    }

    private func captionLine(_ a: Attachment) -> String {
        var parts: [String] = []
        if a.width > 0, a.height > 0 { parts.append("\(a.width)×\(a.height)") }
        parts.append(byteString(a.sizeBytes))
        if a.isVideo { parts.append("video") }
        return parts.joined(separator: " · ")
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Load / cleanup

    private func load() async {
        let loaded = (try? DatabaseService.shared.attachment(id: attachmentId)) ?? nil
        guard let a = loaded else {
            loadFailed = true
            return
        }
        attachment = a
        guard a.isVideo else { return }
        // AVPlayer needs a URL — spill the bytes to a temp file with the right
        // extension so the player can infer the container.
        let ext = URL(fileURLWithPath: a.filename).pathExtension.isEmpty
            ? (UTType(a.mimeType)?.preferredFilenameExtension ?? "mov")
            : URL(fileURLWithPath: a.filename).pathExtension
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pd-view-\(a.id).\(ext)")
        do {
            try a.data.write(to: url, options: .atomic)
            tempVideoURL = url
            player = AVPlayer(url: url)
        } catch {
            // leave player nil → "couldn’t play" placeholder
        }
    }

    private func cleanup() {
        player?.pause()
        if let url = tempVideoURL { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Save a copy

    private func saveCopy() {
        guard let a = attachment else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = a.filename
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try a.data.write(to: url, options: .atomic) }
        catch { appState.errorMessage = error.localizedDescription }
    }
}
