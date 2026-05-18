import SwiftUI
import AppKit

/// Inline Detail view — same content as `ClipDetailSheet`, but
/// rendered in-place as the main area when the user picks the
/// "Detail" view mode (⌘3). Reuses the player controller from
/// BrowserView so transport / LUT / waveform survive view-mode
/// switches.
struct ClipDetailInline: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var playerController: PlayerController
    @State private var details: ClipDetails?
    @State private var isFullscreen: Bool = false

    private var current: Asset? { appState.selectedAsset }
    private var isImageAsset: Bool {
        guard let asset = current else { return false }
        return MediaKind.of(asset: asset) == .image
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
                    metadataPane.frame(width: 360)
                }
            }
        }
        .background(EscapeCatcher { if isFullscreen { isFullscreen = false } })
        .onAppear { loadDetails(); loadPlayer() }
        .onChange(of: current?.path) { _, _ in loadDetails(); loadPlayer() }
        // Parent-side handlers for PlayerCommand cases that need access
        // to AppState (markers / subclips). PlayerView itself only
        // forwards the controller-affecting cases.
        .onReceive(NotificationCenter.default.publisher(for: .playerCommand)) { note in
            guard let cmd = note.object as? PlayerCommand else { return }
            switch cmd {
            case .removeMarker:
                appState.removeMarkerNearestPlayhead(
                    currentTime: playerController.currentTime,
                    fps: playerController.fps
                )
            case .removeLastSubclip:
                appState.removeLastSubclipForSelection()
            default: break
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(current?.filename ?? "—")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
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
        .padding(.vertical, 8)
    }

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
                ImagePreviewView(asset: asset)
            } else {
                PlayerView(
                    controller: playerController,
                    onAddMarker: addMarker,
                    onSaveSubclip: saveSubclip,
                    onJumpMarker: jumpToAdjacentMarker
                )
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack {
            Image(systemName: "photo")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No clip selected").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var fileInfoBlock: some View {
        if let asset = current {
            VStack(alignment: .leading, spacing: 4) {
                row("File", asset.filename)
                row("Size", "\(formatSize(asset.sizeBytes)) (\(asset.sizeBytes) bytes)")
                row("Modified", longDate(asset.modifiedAt))
                if let c = details?.creationDate { row("Created", longDate(c)) }
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
                if let v = videoLabel() { row("Video", v) }
                if let a = audioLabel() { row("Audio", a) }
                if isImageAsset, let w = asset.widthPx, let h = asset.heightPx {
                    row("Resolution", "\(w) × \(h)")
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
            Text(value).textSelection(.enabled)
            Spacer()
        }
    }

    private var metadataPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Metadata")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            Divider()
            MetadataPaneView(
                playerFps: playerController.fps,
                onSeek: { playerController.seek(to: $0) }
            )
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func videoLabel() -> String? {
        guard let asset = current else { return nil }
        var bits: [String] = []
        if let c = details?.videoCodec ?? asset.codec { bits.append(c) }
        if let w = asset.widthPx, let h = asset.heightPx { bits.append("\(w) × \(h)") }
        if let r = asset.frameRate { bits.append(String(format: "%.2f fps", r)) }
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
        appState.addMarker(timecodeIn: playerController.currentTime)
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

    /// Up / Down arrow handler — jumps to the nearest marker (or
    /// in/out) before or after the playhead. Drives both the player's
    /// own key handler and the menu-bar shortcut.
    private func jumpToAdjacentMarker(direction: Int) {
        let times = appState.markers.map(\.timecodeIn)
        _ = playerController.seekToAnchor(direction: direction,
                                            markerTimes: times)
    }

    private func formatSize(_ bytes: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
    private func longDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .full; f.timeStyle = .short
        return f.string(from: d)
    }
    private func timecode(seconds: Double, fps: Double) -> String {
        let t = Int(seconds)
        return String(format: "%02d:%02d:%02d:%02d",
                       t / 3600, (t % 3600) / 60, t % 60,
                       Int((seconds - Double(t)) * fps))
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

/// Bare ESC handler so the inline Detail view can exit fullscreen.
private struct EscapeCatcher: NSViewRepresentable {
    let onEscape: () -> Void
    func makeNSView(context: Context) -> NSView {
        let v = EscView()
        v.onEscape = onEscape
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? EscView)?.onEscape = onEscape
    }
    private final class EscView: NSView {
        var onEscape: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(self)
            }
        }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
        }
    }
}

/// Grid-mode tile. Renders the thumbnail, a selection ring (heavier
/// for the "primary" anchor in a multi-selection), and a transcode
/// progress overlay when the queue has a job for this asset's path.
struct GridCell: View {
    let asset: Asset
    let isSelected: Bool
    var isPrimary: Bool = false
    @ObservedObject var transcodeQueue: TranscodeQueue
    @State private var url: URL?

    private var activeJob: TranscodeJob? {
        if let cur = transcodeQueue.current, cur.source.path == asset.path { return cur }
        return transcodeQueue.pending.first(where: { $0.source.path == asset.path })
    }
    private var finishedJob: TranscodeJob? {
        transcodeQueue.done.last(where: { $0.source.path == asset.path })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
                if let u = url, let img = NSImage(contentsOf: u) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
                transcodeOverlay
            }
            .aspectRatio(16.0/9.0, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: isPrimary ? 3 : (isSelected ? 2 : 0)
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected
                          ? Color.accentColor.opacity(isPrimary ? 0.18 : 0.10)
                          : Color.clear)
            )
            Text(asset.filename)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .onAppear {
            Task {
                let urls = await ThumbnailService.thumbnails(for: asset, count: 12)
                if !urls.isEmpty {
                    await MainActor.run { self.url = urls[urls.count / 2] }
                }
            }
        }
    }

    @ViewBuilder
    private var transcodeOverlay: some View {
        if let job = activeJob {
            ActiveJobOverlay(job: job)
        } else if let done = finishedJob {
            DoneJobBadge(job: done)
        }
    }
}

/// Progress overlay painted on top of an active transcode job's
/// thumbnail. Subscribes to the job directly so its progress value
/// updates without re-rendering the parent.
private struct ActiveJobOverlay: View {
    @ObservedObject var job: TranscodeJob
    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: job.state == .running
                          ? "arrow.triangle.2.circlepath.circle.fill"
                          : "clock.fill")
                        .foregroundStyle(.white)
                        .font(.system(size: 11))
                    Text(stateLabel)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if case .running = job.state {
                        Text("\(Int((job.progress * 100).rounded()))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }
                if case .running = job.state {
                    ProgressView(value: job.progress)
                        .progressViewStyle(.linear)
                        .tint(.orange)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.65))
        }
    }
    private var stateLabel: String {
        switch job.state {
        case .queued:    return "Queued · \(job.preset.name)"
        case .running:   return job.preset.name
        case .finished:  return "Done"
        case .failed:    return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

/// Subtle corner badge once a transcode for this asset finished.
private struct DoneJobBadge: View {
    @ObservedObject var job: TranscodeJob
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Image(systemName: isFailed ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(.white, isFailed ? Color.red : Color.green)
                    .font(.system(size: 16))
                    .padding(4)
            }
            Spacer()
        }
    }
    private var isFailed: Bool {
        if case .failed = job.state { return true }
        if case .cancelled = job.state { return true }
        return false
    }
}

/// AppKit click-with-modifier-flags shim. SwiftUI's `.onTapGesture`
/// doesn't expose modifier flags, so we overlay this transparent
/// `NSView` over the cell and route mouseDown events through it.
/// `onClick` receives the modifier state for plain / Cmd / Shift
/// semantics; `onDoubleClick` fires on double-click (no modifiers).
struct ClickWithModifiers: NSViewRepresentable {
    var onClick: (EventModifiers) -> Void
    var onDoubleClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = ClickCatcher()
        v.onClick = onClick
        v.onDoubleClick = onDoubleClick
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let c = nsView as? ClickCatcher {
            c.onClick = onClick
            c.onDoubleClick = onDoubleClick
        }
    }

    private final class ClickCatcher: NSView {
        var onClick: ((EventModifiers) -> Void)?
        var onDoubleClick: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Stay invisible to layout / hover but receive clicks.
            return self
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount >= 2 {
                onDoubleClick?()
                return
            }
            var mods: EventModifiers = []
            if event.modifierFlags.contains(.command) { mods.insert(.command) }
            if event.modifierFlags.contains(.shift)   { mods.insert(.shift) }
            if event.modifierFlags.contains(.option)  { mods.insert(.option) }
            onClick?(mods)
        }

        // Let right-click fall through to SwiftUI's .contextMenu by
        // not intercepting it here.
        override func rightMouseDown(with event: NSEvent) {
            super.rightMouseDown(with: event)
        }
    }
}
