import SwiftUI
import AVKit
import UniformTypeIdentifiers

/// Hosts an AVPlayer in an AVPlayerLayer-backed NSView. Custom
/// transport sits below; we don't use AVPlayerView so we own the
/// scrubber + keyboard handling. The layer transform applies
/// rotation/flip for preview-only orientation (the underlying file
/// is never touched — transcode keeps the source orientation).
final class PlayerNSView: NSView {
    let playerLayer = AVPlayerLayer()
    var rotationDegrees: Int = 0 { didSet { applyTransform() } }
    var flipHorizontal: Bool = false { didSet { applyTransform() } }
    var flipVertical: Bool = false { didSet { applyTransform() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
        applyTransform()
    }

    private func applyTransform() {
        // Rotate around the layer's anchor point (default 0.5, 0.5).
        // Negative angle because CALayer y-axis flips relative to
        // the math convention.
        var t = CGAffineTransform.identity
        if rotationDegrees != 0 {
            t = t.rotated(by: -CGFloat(rotationDegrees) * .pi / 180)
        }
        if flipHorizontal { t = t.scaledBy(x: -1, y: 1) }
        if flipVertical   { t = t.scaledBy(x: 1, y: -1) }

        CATransaction.begin()
        CATransaction.setDisableActions(true)   // no animation on transform change
        playerLayer.setAffineTransform(t)
        CATransaction.commit()
    }
}

struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    let rotation: Int
    let flipH: Bool
    let flipV: Bool

    func makeNSView(context: Context) -> PlayerNSView {
        let v = PlayerNSView()
        v.playerLayer.player = player
        v.rotationDegrees = rotation
        v.flipHorizontal = flipH
        v.flipVertical = flipV
        return v
    }

    func updateNSView(_ nsView: PlayerNSView, context: Context) {
        if nsView.playerLayer.player !== player {
            nsView.playerLayer.player = player
        }
        if nsView.rotationDegrees != rotation { nsView.rotationDegrees = rotation }
        if nsView.flipHorizontal != flipH { nsView.flipHorizontal = flipH }
        if nsView.flipVertical != flipV { nsView.flipVertical = flipV }
    }
}

@MainActor
final class PlayerController: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying: Bool = false
    @Published var inMarker: Double?
    @Published var outMarker: Double?
    @Published private(set) var currentLUT: LUTData?
    @Published private(set) var waveform: WaveformSamples?
    @Published private(set) var currentRate: Float = 0
    @Published var rotation: Int = 0          // 0 / 90 / 180 / 270
    @Published var flipHorizontal: Bool = false
    @Published var flipVertical: Bool = false

    let player = AVPlayer()
    private var timeObserver: Any?
    private(set) var fps: Double = 30.0
    private var currentURL: URL?
    private var waveformTask: Task<Void, Never>?

    init() {
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            guard let self else { return }
            let seconds = CMTimeGetSeconds(t)
            if seconds.isFinite { self.currentTime = seconds }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

    func load(url: URL, fps: Double) {
        self.fps = fps > 0 ? fps : 30
        self.currentURL = url
        let item = AVPlayerItem(url: url)
        applyLUTToItem(item)
        player.replaceCurrentItem(with: item)
        currentTime = 0
        duration = 0
        isPlaying = false
        inMarker = nil
        outMarker = nil
        currentRate = 0
        waveform = nil
        waveformTask?.cancel()
        waveformTask = Task { [weak self] in
            // Async waveform generation. Cancels cleanly when the
            // player loads a different file before this finishes.
            let samples = await WaveformService.generate(url: url)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.waveform = samples }
        }

        Task { [weak self] in
            do {
                let d = try await item.asset.load(.duration)
                let secs = CMTimeGetSeconds(d)
                await MainActor.run {
                    self?.duration = secs.isFinite ? secs : 0
                }
            } catch {
                NSLog("[PurpleReel] could not load duration: \(error)")
            }
        }
    }

    func setLUT(_ lut: LUTData?) {
        self.currentLUT = lut
        if let item = player.currentItem {
            applyLUTToItem(item)
        }
    }

    /// Rebuild the video composition on `item` to apply (or clear) the
    /// current LUT via a CoreImage filter handler. Re-entered when the
    /// LUT changes or a new asset is loaded.
    private func applyLUTToItem(_ item: AVPlayerItem) {
        guard let lut = currentLUT, let filter = LUTService.filter(for: lut) else {
            item.videoComposition = nil
            return
        }
        let comp = AVVideoComposition(asset: item.asset, applyingCIFiltersWithHandler: { request in
            let source = request.sourceImage.clampedToExtent()
            filter.setValue(source, forKey: kCIInputImageKey)
            let output = (filter.outputImage ?? source).cropped(to: request.sourceImage.extent)
            request.finish(with: output, context: nil)
        })
        item.videoComposition = comp
    }

    func togglePlay() {
        if isPlaying {
            player.pause()
            player.rate = 0
            currentRate = 0
            isPlaying = false
        } else {
            player.rate = 1.0
            currentRate = 1.0
            player.play()
            isPlaying = true
        }
    }

    /// J/L multi-rate shuttle. Pressing J/L repeatedly ramps the rate
    /// up through -1×/-2×/-4× / +1×/+2×/+4× — matches FCP and Premiere
    /// transport semantics. K (or any rate-zero call) resets.
    func shuttle(direction: Int) {
        let steps: [Float] = [0.25, 0.5, 1.0, 2.0, 4.0]
        let sign = Float(direction)
        // Find current absolute step; if rate is in the wrong sign,
        // restart from 1× in the requested direction.
        let absRate = abs(currentRate)
        var stepIdx = steps.firstIndex(where: { abs($0 - absRate) < 0.01 })
                      ?? (steps.firstIndex(of: 1.0) ?? 2)
        let sameDirection = (currentRate == 0) ||
            (currentRate > 0 && direction > 0) ||
            (currentRate < 0 && direction < 0)
        if sameDirection {
            stepIdx = min(steps.count - 1, stepIdx + 1)
        } else {
            stepIdx = steps.firstIndex(of: 1.0) ?? 2
        }
        let newRate = sign * steps[stepIdx]
        setRate(newRate)
    }

    func seek(to seconds: Double, snapToFrame: Bool = true) {
        let target = max(0, min(seconds, duration))
        let tolerance = snapToFrame ? CMTime.zero : CMTime(seconds: 0.05, preferredTimescale: 600)
        let cm = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: tolerance, toleranceAfter: tolerance)
        currentTime = target
    }

    func step(frames: Int) {
        seek(to: currentTime + Double(frames) * Timecode.frameDuration(fps: fps))
    }

    func setRate(_ rate: Float) {
        player.rate = rate
        currentRate = rate
        isPlaying = rate != 0
    }

    func markIn()  { inMarker  = currentTime }
    func markOut() { outMarker = currentTime }
    func clearInOut() { inMarker = nil; outMarker = nil }
}

struct PlayerView: View {
    @ObservedObject var controller: PlayerController
    let onAddMarker: () -> Void
    let onSaveSubclip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PlayerSurface(player: controller.player,
                           rotation: controller.rotation,
                           flipH: controller.flipHorizontal,
                           flipV: controller.flipVertical)
                .frame(minHeight: 280)
                .background(Color.black)

            Scrubber(controller: controller)
                .frame(height: 38)
                .padding(.horizontal, 8)
                .padding(.top, 6)

            transportBar
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            lutBar
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
        }
        .background(KeyHandler { event in
            handleKey(event)
        })
        .onAppear {
            // Restore the most-recently-used LUT, if any, so the user
            // doesn't have to re-pick across launches.
            if controller.currentLUT == nil,
               let path = UserDefaults.standard.string(forKey: "lastLUTPath") {
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: url.path) {
                    if let lut = try? LUTService.load(url: url) {
                        controller.setLUT(lut)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var lutBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "paintpalette")
                .foregroundStyle(.secondary)
            if let lut = controller.currentLUT {
                Text(lut.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("(\(lut.size)³)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button {
                    controller.setLUT(nil)
                    UserDefaults.standard.removeObject(forKey: "lastLUTPath")
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Clear LUT")
            } else {
                Text("No LUT applied")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Load LUT…") { pickLUT() }
                .controlSize(.small)
        }
    }

    private var viewMenu: some View {
        Menu {
            Section("Rotate") {
                ForEach([0, 90, 180, 270], id: \.self) { deg in
                    Button {
                        controller.rotation = deg
                    } label: {
                        if controller.rotation == deg {
                            Label("\(deg)°", systemImage: "checkmark")
                        } else {
                            Text("\(deg)°")
                        }
                    }
                }
            }
            Section("Flip") {
                Toggle("Horizontal", isOn: Binding(
                    get: { controller.flipHorizontal },
                    set: { controller.flipHorizontal = $0 }
                ))
                Toggle("Vertical", isOn: Binding(
                    get: { controller.flipVertical },
                    set: { controller.flipVertical = $0 }
                ))
            }
            if controller.rotation != 0 || controller.flipHorizontal || controller.flipVertical {
                Divider()
                Button("Reset Orientation") {
                    controller.rotation = 0
                    controller.flipHorizontal = false
                    controller.flipVertical = false
                }
            }
        } label: {
            Image(systemName: "rotate.right")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 36)
        .help("View → Rotate / Flip. Preview only — output files keep source orientation.")
    }

    private func pickLUT() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "cube") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let lut = try LUTService.load(url: url)
            controller.setLUT(lut)
            UserDefaults.standard.set(url.path, forKey: "lastLUTPath")
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not load LUT"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @ViewBuilder
    private var transportBar: some View {
        HStack(spacing: 10) {
            Button { controller.step(frames: -1) } label: {
                Image(systemName: "backward.frame.fill")
            }
            .help("Step back 1 frame (←)")

            Button { controller.togglePlay() } label: {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 20)
            }
            .keyboardShortcut(.space, modifiers: [])
            .help("Play / Pause (Space)")

            Button { controller.step(frames: 1) } label: {
                Image(systemName: "forward.frame.fill")
            }
            .help("Step forward 1 frame (→)")

            Divider().frame(height: 16)

            Text(Timecode.format(seconds: controller.currentTime, fps: controller.fps))
                .font(.system(.body, design: .monospaced))
            Text("/")
                .foregroundStyle(.secondary)
            Text(Timecode.format(seconds: controller.duration, fps: controller.fps))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            viewMenu

            Button { controller.markIn() } label: { Text("I") }
                .help("Mark in (I)")
            Button { controller.markOut() } label: { Text("O") }
                .help("Mark out (O)")
            Button {
                onSaveSubclip()
            } label: { Image(systemName: "scissors") }
            .disabled(controller.inMarker == nil || controller.outMarker == nil)
            .help("Save subclip from I-O range (S)")
            Button {
                onAddMarker()
            } label: { Image(systemName: "bookmark") }
            .help("Add marker at playhead (M)")
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let chars = event.charactersIgnoringModifiers else { return false }
        switch chars.lowercased() {
        case "j": controller.shuttle(direction: -1); return true
        case "k": controller.setRate(0);             return true
        case "l": controller.shuttle(direction: 1);  return true
        case "i": controller.markIn();               return true
        case "o": controller.markOut();              return true
        case "m": onAddMarker();                     return true
        case "s":
            if controller.inMarker != nil && controller.outMarker != nil {
                onSaveSubclip(); return true
            }
            return false
        default: break
        }
        switch event.keyCode {
        case 123: controller.step(frames: -1); return true // ←
        case 124: controller.step(frames: 1);  return true // →
        default: return false
        }
    }
}

/// Custom scrubber with waveform, playhead, I/O range, and click-to-seek.
struct Scrubber: View {
    @ObservedObject var controller: PlayerController
    @State private var draggingX: CGFloat? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.18))

                // Audio waveform (paints behind everything else).
                if let wave = controller.waveform {
                    WaveformShape(peaks: wave.peaks)
                        .fill(Color.secondary.opacity(0.55))
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                // I/O range overlay
                if let inT = controller.inMarker, let outT = controller.outMarker,
                   controller.duration > 0 {
                    let lo = min(inT, outT)
                    let hi = max(inT, outT)
                    let x0 = CGFloat(lo / controller.duration) * geo.size.width
                    let x1 = CGFloat(hi / controller.duration) * geo.size.width
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.35))
                        .frame(width: max(0, x1 - x0))
                        .offset(x: x0)
                }

                // Playhead
                if controller.duration > 0 {
                    let x = CGFloat(controller.currentTime / controller.duration) * geo.size.width
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2)
                        .offset(x: max(0, x - 1))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                guard controller.duration > 0 else { return }
                let x = max(0, min(geo.size.width, v.location.x))
                draggingX = x
                let target = Double(x / geo.size.width) * controller.duration
                controller.seek(to: target)
            }.onEnded { _ in draggingX = nil })
        }
    }
}

/// Vertically-mirrored peak bars from a downsampled waveform.
struct WaveformShape: Shape {
    let peaks: [Float]

    func path(in rect: CGRect) -> Path {
        guard !peaks.isEmpty else { return Path() }
        let mid = rect.midY
        let halfH = rect.height / 2
        let step = rect.width / CGFloat(peaks.count)
        var p = Path()
        for (i, peak) in peaks.enumerated() {
            let x = CGFloat(i) * step
            let h = CGFloat(peak) * halfH
            p.addRect(CGRect(x: x, y: mid - h, width: max(1, step - 0.4), height: h * 2))
        }
        return p
    }
}

/// NSViewRepresentable that intercepts key events for player shortcuts.
/// Returning `true` from the handler swallows the event.
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
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }
}
