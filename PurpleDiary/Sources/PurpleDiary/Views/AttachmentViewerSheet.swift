import SwiftUI
import AVKit
import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Full-size viewer for one attachment: a fit-to-window image for photos, an
/// AVKit player for video/audio, a PDFKit view for PDFs, or a doc-icon card for
/// any other file. The full `data` BLOB is loaded once on appear; for video/audio
/// it's written to a temp file (AVPlayer needs a URL) that's cleaned up on
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
            } else if attachment.isAudio {
                if let player {
                    AudioPlayerView(player: player, filename: attachment.filename)
                } else {
                    placeholder("speaker.slash", "Couldn’t play this audio.")
                }
            } else if attachment.isPDF {
                if let doc = PDFDocument(data: attachment.data) {
                    PDFKitView(document: doc)
                } else {
                    placeholder("doc.richtext", "Couldn’t open this PDF.")
                }
            } else if attachment.isFile {
                fileCard(attachment)
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

    /// Doc-icon card for a non-previewable file attachment.
    private func fileCard(_ a: Attachment) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "doc")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(.secondary)
            Text(a.filename).font(.headline).lineLimit(2).multilineTextAlignment(.center)
            Text("\(byteString(a.sizeBytes)) · use “Save a Copy…” to open it in another app")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: 380)
    }

    private func captionLine(_ a: Attachment) -> String {
        var parts: [String] = []
        if a.width > 0, a.height > 0 { parts.append("\(a.width)×\(a.height)") }
        parts.append(byteString(a.sizeBytes))
        if a.isVideo { parts.append("video") }
        else if a.isAudio { parts.append("audio") }
        else if a.isPDF { parts.append(a.height > 0 ? "\(a.height)-page PDF" : "PDF") }
        else if a.isFile { parts.append("file") }
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
        guard a.isVideo || a.isAudio else { return }
        // AVPlayer needs a URL — spill the bytes to a temp file with the right
        // extension so the player can infer the container.
        let fallbackExt = a.isAudio ? "m4a" : "mov"
        let ext = URL(fileURLWithPath: a.filename).pathExtension.isEmpty
            ? (UTType(a.mimeType)?.preferredFilenameExtension ?? fallbackExt)
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

/// Wraps a `PDFView` (AppKit) so a PDF attachment renders in the SwiftUI viewer.
struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = document
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}

/// A compact audio transport: a music-note hero card plus play/pause, a
/// draggable scrubber, and elapsed / remaining time. AVKit's `VideoPlayer`
/// renders a black rectangle for audio, so this gives audio a proper face.
struct AudioPlayerView: View {
    let player: AVPlayer
    let filename: String

    @State private var isPlaying = false
    @State private var current: Double = 0      // seconds
    @State private var duration: Double = 0      // seconds
    @State private var scrubbing = false
    @State private var observer: Any?

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 160, height: 160)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
            Text(filename)
                .font(.headline).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 420)

            VStack(spacing: 4) {
                Slider(value: $current, in: 0...max(duration, 0.1)) { editing in
                    scrubbing = editing
                    if !editing {
                        player.seek(to: CMTime(seconds: current, preferredTimescale: 600))
                    }
                }
                .frame(maxWidth: 420)
                HStack {
                    Text(timeString(current)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Text(timeString(duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 420)
            }

            Button(action: toggle) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 52))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            Spacer()
        }
        .padding(24)
        .task { await setup() }
        .onDisappear {
            if let observer { player.removeTimeObserver(observer) }
            player.pause()
        }
    }

    private func setup() async {
        if let secs = try? await player.currentItem?.asset.load(.duration).seconds,
           secs.isFinite { duration = secs }
        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main
        ) { time in
            if !scrubbing { current = time.seconds }
            if duration <= 0.1, let d = player.currentItem?.duration.seconds, d.isFinite { duration = d }
        }
        player.play()
        isPlaying = true
    }

    private func toggle() {
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
