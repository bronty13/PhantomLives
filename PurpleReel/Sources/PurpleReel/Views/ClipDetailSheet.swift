import SwiftUI
import AppKit
import AVKit

/// Kyno-style single-clip Detail view. Opens on double-click in the
/// asset table (or `⌘3`). Layout matches Kyno's reference:
///   - Top: large preview (image or video w/ full transport)
///   - Middle: file metadata as a flat field list
///   - Right: Metadata pane (Title/Description/Rating/Tags)
///   - Header has prev/next + fullscreen toggle (⌘F)
/// In fullscreen mode the metadata pane + file-info hide and the
/// preview fills the sheet.
struct ClipDetailSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playerController = PlayerController()
    @State private var details: ClipDetails?
    @State private var isFullscreen: Bool = false

    private var navList: [Asset] { appState.displayedAssets }
    private var current: Asset? { appState.selectedAsset }
    private var currentIndex: Int? {
        guard let cur = current else { return nil }
        return navList.firstIndex(where: { $0.path == cur.path })
    }
    private var isImageAsset: Bool {
        guard let asset = current else { return false }
        let ext = (asset.filename as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "heic", "tif", "tiff", "gif", "bmp"]
            .contains(ext)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isFullscreen {
                header
                Divider()
            }
            HStack(spacing: 0) {
                centerPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !isFullscreen {
                    Divider()
                    metadataPane
                        .frame(width: 360)
                }
            }
        }
        .frame(minWidth: 1100, minHeight: 700)
        .background(KeyHandler { event in
            if event.keyCode == 53 {   // Esc
                if isFullscreen {
                    isFullscreen = false
                    return true
                }
            }
            return false
        })
        .onAppear { loadDetails(); loadPlayer() }
        .onChange(of: current?.path) { _, _ in loadDetails(); loadPlayer() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Text(current?.filename ?? "—")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let idx = currentIndex {
                Text("\(idx + 1) of \(navList.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button { goPrev() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(!canGoPrev)
            Button { goNext() } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .disabled(!canGoNext)

            Divider().frame(height: 16)

            // Fullscreen toggle: arrows-out icon (Kyno calls this
            // "Enter Full Screen" — but for a sheet we just blow the
            // preview up to fill the window. ESC exits.).
            Button { isFullscreen.toggle() } label: {
                Image(systemName: isFullscreen
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("f", modifiers: [.command])
            .help(isFullscreen ? "Exit fullscreen (⌘F / Esc)" : "Fullscreen (⌘F)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Center pane

    @ViewBuilder
    private var centerPane: some View {
        VStack(spacing: 0) {
            previewArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

            if !isFullscreen {
                Divider()
                fileInfoBlock
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.bar)
            }
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        if let asset = current {
            if isImageAsset {
                if let img = NSImage(contentsOf: URL(fileURLWithPath: asset.path)) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    placeholder("Could not load image")
                }
            } else {
                // Full PlayerView gives us the transport bar +
                // scrubber + LUT controls + view menu (rotate/flip) —
                // matches what the user expects in the Detail view.
                PlayerView(
                    controller: playerController,
                    onAddMarker: addMarker,
                    onSaveSubclip: saveSubclip,
                    onSetPosterFrame: { seconds in
                        appState.setPosterFrameForSelected(seconds: seconds)
                    }
                )
            }
        } else {
            placeholder("No clip selected")
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Image(systemName: "photo")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - File info (flat field list)

    @ViewBuilder
    private var fileInfoBlock: some View {
        if let asset = current {
            VStack(alignment: .leading, spacing: 4) {
                row("File", asset.filename)
                row("Size", "\(formatSize(asset.sizeBytes)) (\(asset.sizeBytes) bytes)")
                row("Modified", longDate(asset.modifiedAt))
                if let c = details?.creationDate {
                    row("Created", longDate(c))
                }
                if let f = details?.container ?? containerLabel(asset.path) {
                    row("File format", f)
                }
                if let dur = asset.durationSeconds, dur > 0 {
                    row("Duration", timecode(seconds: dur, fps: asset.frameRate ?? 30))
                }
                let total = (details?.videoBitrateBps ?? 0) + (details?.audioBitrateBps ?? 0)
                if total > 0 {
                    row("Total bitrate", String(format: "%.2f MBit/s", total / 1_000_000))
                }
                if let videoLine = videoLabel() {
                    row("Video", videoLine)
                }
                if let audioLine = audioLabel() {
                    row("Audio", audioLine)
                }
                if isImageAsset {
                    if let w = asset.widthPx, let h = asset.heightPx {
                        row("Resolution", "\(w) × \(h)")
                    }
                }
            }
            .font(.caption)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label + ":")
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func videoLabel() -> String? {
        guard let asset = current else { return nil }
        var bits: [String] = []
        if let c = details?.videoCodec ?? asset.codec { bits.append(c) }
        if let w = asset.widthPx, let h = asset.heightPx {
            bits.append("\(w) × \(h)")
        }
        if let r = asset.frameRate {
            bits.append(String(format: "%.2f fps", r))
        }
        if let vb = details?.videoBitrateBps, vb > 0 {
            bits.append(String(format: "%.2f MBit/s", vb / 1_000_000))
        }
        return bits.isEmpty ? nil : bits.joined(separator: ", ")
    }

    private func audioLabel() -> String? {
        guard let a = details?.audioCodec else { return nil }
        var bits: [String] = [a]
        if let r = details?.audioSampleRate {
            bits.append(String(format: "%.1f kHz", r / 1_000))
        }
        if let ch = details?.audioChannels {
            bits.append(ch == 1 ? "Mono" : (ch == 2 ? "2.0 Stereo" : "\(ch) ch"))
        }
        if let ab = details?.audioBitrateBps, ab > 0 {
            bits.append(String(format: "%.0f kBit/s", ab / 1_000))
        }
        return bits.joined(separator: ", ")
    }

    // MARK: - Metadata pane (right)

    private var metadataPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Metadata")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TagsRatingView()
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Navigation

    private var canGoPrev: Bool {
        guard let idx = currentIndex else { return false }
        return idx > 0
    }
    private var canGoNext: Bool {
        guard let idx = currentIndex else { return false }
        return idx < navList.count - 1
    }
    private func goPrev() {
        guard let idx = currentIndex, idx > 0 else { return }
        appState.selectedAssetPath = navList[idx - 1].path
    }
    private func goNext() {
        guard let idx = currentIndex, idx < navList.count - 1 else { return }
        appState.selectedAssetPath = navList[idx + 1].path
    }

    // MARK: - Lifecycle

    private func loadDetails() {
        details = nil
        guard let asset = current else { return }
        Task {
            let d = await ClipDetailsService.load(asset: asset)
            await MainActor.run { self.details = d }
        }
    }

    private func loadPlayer() {
        guard let asset = current, !isImageAsset else { return }
        playerController.load(url: URL(fileURLWithPath: asset.path),
                                fps: asset.frameRate ?? 30)
    }

    private func addMarker() {
        guard let asset = current, let id = asset.rowId else { return }
        appState.addMarker(timecodeIn: playerController.currentTime)
        _ = id
    }

    private func saveSubclip() {
        guard let inT = playerController.inMarker,
              let outT = playerController.outMarker,
              let asset = current else { return }
        let base = asset.filename
        let name = "\(base) [\(Timecode.format(seconds: min(inT, outT), fps: playerController.fps))]"
        appState.addSubclip(name: name, timecodeIn: inT, timecodeOut: outT)
        playerController.clearInOut()
    }

    // MARK: - Helpers

    private func formatSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    private func longDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        return f.string(from: d)
    }

    private func timecode(seconds: Double, fps: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        let frames = Int((seconds - Double(total)) * fps)
        return String(format: "%02d:%02d:%02d:%02d", h, m, s, frames)
    }

    private func containerLabel(_ path: String) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "m4v": return "MPEG-4"
        case "mov", "qt": return "QuickTime Movie"
        case "jpg", "jpeg": return "JPEG image"
        case "png": return "PNG image"
        case "heic": return "HEIC image"
        case "tif", "tiff": return "TIFF image"
        case "mxf": return "MXF"
        default: return ext.uppercased()
        }
    }
}

/// Hidden NSView that captures ESC for fullscreen exit.
private struct KeyHandler: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyCaptureView {
        let v = KeyCaptureView()
        v.onKeyDown = onKeyDown
        return v
    }
    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onKeyDown = onKeyDown
    }
}

private final class KeyCaptureView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self)
        }
    }
    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }
}
