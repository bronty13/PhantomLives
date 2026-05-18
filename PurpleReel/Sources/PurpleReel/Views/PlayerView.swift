import SwiftUI
import AVKit
import UniformTypeIdentifiers

/// How the video frame is sized inside the player surface.
///
/// - `fit`: aspect-fit (letterbox / pillarbox to preserve aspect).
///   Default — the rectangle fills the surface without cropping.
/// - `fill`: aspect-fill (crops). Good for previewing reframes.
/// - `actualSize`: 1:1 pixel-for-pixel. Video may exceed the surface;
///   excess is centered and clipped at the bounds. Useful for QC at
///   100% — a 4K video in a 1080p preview no longer downsamples.
enum ZoomMode: String, CaseIterable, Identifiable {
    case fit, fill, actualSize
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fit:        return "Fit Window"
        case .fill:       return "Fill Window"
        case .actualSize: return "Actual Size (100%)"
        }
    }
    var icon: String {
        switch self {
        case .fit:        return "rectangle.arrowtriangle.2.inward"
        case .fill:       return "rectangle.arrowtriangle.2.outward"
        case .actualSize: return "1.square"
        }
    }
}

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
    var zoomMode: ZoomMode = .fit { didSet { needsLayout = true } }
    /// Natural pixel size of the current video track. Used only by
    /// `.actualSize` mode; ignored for fit / fill. Zero until the
    /// asset loads.
    var videoNaturalSize: CGSize = .zero { didSet { needsLayout = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true   // clip actualSize overflow cleanly
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        applyZoom()
        applyTransform()
    }

    private func applyZoom() {
        switch zoomMode {
        case .fit:
            playerLayer.videoGravity = .resizeAspect
            playerLayer.frame = bounds
        case .fill:
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.frame = bounds
        case .actualSize:
            // Render the layer at the video's natural pixel size,
            // centered. If the source is larger than the surface
            // the excess is clipped by the parent layer's
            // `masksToBounds`. If natural size hasn't been resolved
            // yet, fall back to bounds so the user still sees the
            // frame instead of black until the size arrives.
            playerLayer.videoGravity = .resizeAspect
            let s = videoNaturalSize
            guard s.width > 0, s.height > 0 else {
                playerLayer.frame = bounds
                return
            }
            let x = (bounds.width - s.width) / 2
            let y = (bounds.height - s.height) / 2
            playerLayer.frame = CGRect(x: x, y: y,
                                        width: s.width, height: s.height)
        }
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
    let zoomMode: ZoomMode
    let naturalSize: CGSize

    func makeNSView(context: Context) -> PlayerNSView {
        let v = PlayerNSView()
        v.playerLayer.player = player
        v.rotationDegrees = rotation
        v.flipHorizontal = flipH
        v.flipVertical = flipV
        v.zoomMode = zoomMode
        v.videoNaturalSize = naturalSize
        return v
    }

    func updateNSView(_ nsView: PlayerNSView, context: Context) {
        if nsView.playerLayer.player !== player {
            nsView.playerLayer.player = player
        }
        if nsView.rotationDegrees != rotation { nsView.rotationDegrees = rotation }
        if nsView.flipHorizontal != flipH { nsView.flipHorizontal = flipH }
        if nsView.flipVertical != flipV { nsView.flipVertical = flipV }
        if nsView.zoomMode != zoomMode { nsView.zoomMode = zoomMode }
        if nsView.videoNaturalSize != naturalSize {
            nsView.videoNaturalSize = naturalSize
        }
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
    /// Loop mode: when on, the AVPlayer auto-seeks back to the start
    /// (or to `inMarker` when an I/O range is set) on item end.
    @Published var loopMode: Bool = false
    /// Zoom / fit mode for the player surface. Hydrated from
    /// `playerZoomMode` AppStorage on init so the user's preference
    /// sticks across clips and launches. See `ZoomMode`.
    @Published var zoomMode: ZoomMode = {
        let raw = UserDefaults.standard.string(forKey: "playerZoomMode") ?? ""
        return ZoomMode(rawValue: raw) ?? .fit
    }() {
        didSet {
            UserDefaults.standard.set(zoomMode.rawValue, forKey: "playerZoomMode")
        }
    }
    /// Natural pixel size of the current video track. Pulled from
    /// `AVAssetTrack.naturalSize` after each load; consumed only by
    /// the `.actualSize` zoom mode.
    @Published var videoNaturalSize: CGSize = .zero

    /// Zebra overlay (highlights pixels with luma > threshold).
    /// Toggle + threshold persist in defaults so a colorist can set
    /// up once and have the same monitoring config across clips.
    @Published var zebraEnabled: Bool = UserDefaults.standard.bool(forKey: "playerZebraEnabled") {
        didSet {
            UserDefaults.standard.set(zebraEnabled, forKey: "playerZebraEnabled")
            reapplyEffects()
        }
    }
    @Published var zebraThreshold: Double = {
        let raw = UserDefaults.standard.object(forKey: "playerZebraThreshold") as? Double
        return raw ?? 0.95   // 95 IRE = standard "clipping warning" preset
    }() {
        didSet {
            UserDefaults.standard.set(zebraThreshold, forKey: "playerZebraThreshold")
            reapplyEffects()
        }
    }
    /// Target display aspect for the widescreen matte preview. Zero =
    /// off (no bars). See `WidescreenAspect` for canonical values.
    @Published var matteAspect: Double = UserDefaults.standard.double(forKey: "playerMatteAspect") {
        didSet {
            UserDefaults.standard.set(matteAspect, forKey: "playerMatteAspect")
            reapplyEffects()
        }
    }

    private func reapplyEffects() {
        if let item = player.currentItem { applyEffectsToItem(item) }
    }

    let player = AVPlayer()
    /// Audio mute state. Toggled by X key (Kyno-compat) and any
    /// future Audio menu item. Persists via the player object only
    /// — clip-scope, not app-scope.
    @Published var isMuted: Bool = false {
        didSet { player.isMuted = isMuted }
    }
    func toggleMute() { isMuted.toggle() }

    /// Cycle the widescreen-matte aspect through the four most-used
    /// cinema values. Off → 1.85 → 2.35 → 2.39 → Off. Driven by the
    /// ⌃⌥W Kyno shortcut; the full picker stays in the monitoring
    /// menu for less-common ratios.
    func cycleMatteAspect() {
        let cycle: [Double] = [0, 1.85, 2.35, 2.39]
        let idx = cycle.firstIndex(where: {
            abs($0 - matteAspect) < 0.001
        }) ?? 0
        matteAspect = cycle[(idx + 1) % cycle.count]
    }

    private var didPlayToEndObserver: NSObjectProtocol?
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
        // Loop-mode handler. Subscribed once; when `loopMode` is on we
        // seek to the start (or to the I-marker if set) on end-of-item
        // and resume playback. When off this is a no-op.
        didPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.loopMode else { return }
                let restart = self.inMarker ?? 0
                self.seek(to: restart)
                self.setRate(1.0)
            }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let didPlayToEndObserver { NotificationCenter.default.removeObserver(didPlayToEndObserver) }
    }

    func toggleLoop() { loopMode.toggle() }

    /// Rotate the preview ±90° around the current orientation.
    /// Wraps within [0, 90, 180, 270]. Preview-only — never touches
    /// the underlying file.
    func rotateBy(_ degrees: Int) {
        let next = ((rotation + degrees) % 360 + 360) % 360
        rotation = next
    }

    /// Capture the player's current displayed frame and save it as PNG.
    /// Uses AVAssetImageGenerator with `requestedTimeToleranceBefore/
    /// After = .zero` for frame accuracy.
    func exportCurrentFrame() {
        guard let url = currentURL else { return }
        let time = CMTime(seconds: currentTime, preferredTimescale: 600)
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        let stamp = String(format: "%.3f", currentTime).replacingOccurrences(of: ".", with: "_")
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(url.deletingPathExtension().lastPathComponent)_t\(stamp).png"
        guard panel.runModal() == .OK, let dst = panel.url else { return }
        do {
            let cg = try gen.copyCGImage(at: time, actualTime: nil)
            let rep = NSBitmapImageRep(cgImage: cg)
            guard let png = rep.representation(using: .png, properties: [:]) else { return }
            try png.write(to: dst)
            NSWorkspace.shared.activateFileViewerSelecting([dst])
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't export frame"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    func load(url: URL, fps: Double) {
        self.fps = fps > 0 ? fps : 30
        self.currentURL = url
        let item = AVPlayerItem(url: url)
        applyEffectsToItem(item)
        player.replaceCurrentItem(with: item)
        currentTime = 0
        duration = 0
        isPlaying = false
        inMarker = nil
        outMarker = nil
        currentRate = 0
        waveform = nil
        // Clear the previous clip's natural size — the new value
        // arrives via the async track-load below. Leaving the old
        // value in place would size `.actualSize` to the wrong frame.
        videoNaturalSize = .zero
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

        // Resolve the video track's natural size for `.actualSize`
        // zoom. AVAssetTrack.naturalSize is the encoded pixel
        // dimensions, ignoring the `preferredTransform` rotation; we
        // pass the raw size since the player layer applies its own
        // rotation via `applyTransform()` and we don't want to
        // double-rotate. Falls back to zero on failure, which makes
        // `.actualSize` mode behave like `.fit` until the next clip.
        Task { [weak self] in
            do {
                let tracks = try await item.asset.loadTracks(withMediaType: .video)
                if let track = tracks.first {
                    let size = try await track.load(.naturalSize)
                    await MainActor.run {
                        self?.videoNaturalSize = CGSize(
                            width: abs(size.width),
                            height: abs(size.height)
                        )
                    }
                }
            } catch {
                NSLog("[PurpleReel] could not load video natural size: \(error)")
            }
        }
    }

    func setLUT(_ lut: LUTData?) {
        self.currentLUT = lut
        if let item = player.currentItem {
            applyEffectsToItem(item)
        }
    }

    /// Rebuild the video composition on `item` to apply the current
    /// preview-only effect stack: LUT (color) → zebra (exposure
    /// monitoring) → widescreen matte (framing preview). Re-entered
    /// when any of those properties change or a new asset loads. If
    /// every effect is off, drops the composition entirely so playback
    /// uses the direct AVPlayer path (no CoreImage cost per frame).
    private func applyEffectsToItem(_ item: AVPlayerItem) {
        let lutFilter = currentLUT.flatMap { LUTService.filter(for: $0) }
        let zebraOn = zebraEnabled
        let matteOn = matteAspect > 0
        guard lutFilter != nil || zebraOn || matteOn else {
            item.videoComposition = nil
            return
        }
        // Capture monitoring state out of the closure scope so the
        // filter handler doesn't reach back into `self` on the render
        // queue.
        let zThresh = zebraThreshold
        let mAspect = matteAspect
        let comp = AVVideoComposition(asset: item.asset, applyingCIFiltersWithHandler: { request in
            var image = request.sourceImage.clampedToExtent()
            if let f = lutFilter {
                f.setValue(image, forKey: kCIInputImageKey)
                image = f.outputImage ?? image
            }
            image = MonitoringEffects.apply(
                to: image,
                zebraEnabled: zebraOn,
                zebraThreshold: zThresh,
                matteAspect: mAspect
            )
            request.finish(with: image.cropped(to: request.sourceImage.extent),
                            context: nil)
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

    /// 5-second jump used by Shift+← / Shift+→ — coarser than frame
    /// step, fine-grained enough to scan a long take.
    func jumpSeconds(_ delta: Double) {
        seek(to: currentTime + delta, snapToFrame: false)
    }

    /// Seek to the nearest anchor time (markers + in-marker +
    /// out-marker) in `direction` (-1 = previous, +1 = next). Returns
    /// `true` if it moved, `false` if no anchor exists in that
    /// direction. Anchors are the union of marker timecodes plus the
    /// I/O range so Up/Down navigates everything the user has
    /// pinned without an extra keystroke.
    @discardableResult
    func seekToAnchor(direction: Int, markerTimes: [Double]) -> Bool {
        var anchors = markerTimes
        if let inT  = inMarker  { anchors.append(inT) }
        if let outT = outMarker { anchors.append(outT) }
        anchors.sort()
        guard !anchors.isEmpty else { return false }
        // Small epsilon so a jump can land "on" the current position
        // without immediately re-firing into the same anchor.
        let eps = 0.05
        if direction > 0 {
            if let next = anchors.first(where: { $0 > currentTime + eps }) {
                seek(to: next, snapToFrame: false)
                return true
            }
        } else {
            if let prev = anchors.last(where: { $0 < currentTime - eps }) {
                seek(to: prev, snapToFrame: false)
                return true
            }
        }
        return false
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
    /// Direction = -1 (previous) or +1 (next). Parent supplies the
    /// active marker list so the player stays decoupled from the
    /// catalogue / AppState.
    var onJumpMarker: (Int) -> Void = { _ in }
    /// "shuttle" = multi-rate J/L (PurpleReel default, matches FCP /
    /// Premiere); "jump5s" = J/L jump 5 seconds (Kyno's default).
    /// Bound to the user-toggleable Playback menu item.
    @AppStorage("playerJLMode") private var jlMode: String = "shuttle"

    var body: some View {
        VStack(spacing: 0) {
            PlayerSurface(player: controller.player,
                           rotation: controller.rotation,
                           flipH: controller.flipHorizontal,
                           flipV: controller.flipVertical,
                           zoomMode: controller.zoomMode,
                           naturalSize: controller.videoNaturalSize)
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
        // Route menu-bar PlayerCommand notifications to the controller.
        .onReceive(NotificationCenter.default.publisher(for: .playerCommand)) { note in
            guard let cmd = note.object as? PlayerCommand else { return }
            switch cmd {
            case .playInToOut:
                if let inT = controller.inMarker {
                    controller.seek(to: inT)
                    controller.setRate(1.0)
                }
            case .toggleLoop:
                controller.toggleLoop()
            case .setIn:        controller.markIn()
            case .setOut:       controller.markOut()
            case .clearInOut:   controller.clearInOut()
            case .addMarker:    onAddMarker()
            case .saveSubclip:  onSaveSubclip()
            case .exportFrame:  controller.exportCurrentFrame()
            case .removeMarker: break   // wired by inspector; player is no-op
            case .jumpBack5s:    controller.jumpSeconds(-5)
            case .jumpForward5s: controller.jumpSeconds(5)
            case .jumpPrevMarker: onJumpMarker(-1)
            case .jumpNextMarker: onJumpMarker(1)
            case .rotateLeft:    controller.rotateBy(-90)
            case .rotateRight:   controller.rotateBy(90)
            case .toggleMute:    controller.toggleMute()
            case .toggleZebra:   controller.zebraEnabled.toggle()
            case .cycleMatte:    controller.cycleMatteAspect()
            // removeLastSubclip is parent-handled (AppState owns the
            // subclip list). PlayerView ignores it cleanly.
            case .removeLastSubclip: break
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

    private var monitoringMenu: some View {
        Menu {
            Section("Zebra (Overexposure)") {
                Toggle("Enabled", isOn: Binding(
                    get: { controller.zebraEnabled },
                    set: { controller.zebraEnabled = $0 }
                ))
                .disabled(false)
                Section("Threshold") {
                    ForEach([0.50, 0.70, 0.80, 0.95, 1.00], id: \.self) { v in
                        Button {
                            controller.zebraThreshold = v
                            if !controller.zebraEnabled {
                                controller.zebraEnabled = true
                            }
                        } label: {
                            let label = "\(Int(v * 100)) IRE"
                            if abs(controller.zebraThreshold - v) < 0.001 {
                                Label(label, systemImage: "checkmark")
                            } else {
                                Text(label)
                            }
                        }
                    }
                }
            }
            Section("Widescreen Matte") {
                Button {
                    controller.matteAspect = 0
                } label: {
                    if controller.matteAspect == 0 {
                        Label("Off", systemImage: "checkmark")
                    } else {
                        Text("Off")
                    }
                }
                ForEach(WidescreenAspect.allCases) { a in
                    Button {
                        controller.matteAspect = a.rawValue
                    } label: {
                        if abs(controller.matteAspect - a.rawValue) < 0.001 {
                            Label(a.label, systemImage: "checkmark")
                        } else {
                            Text(a.label)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: monitoringIcon)
                .foregroundStyle(monitoringActive ? Color.orange : Color.primary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 36)
        .help("Monitoring — zebra stripes + widescreen matte. Preview only; transcode keeps source pixels.")
    }

    /// Whichever monitoring badge to show on the toolbar icon. Zebra
    /// takes priority because it's a continuous visual; matte is a
    /// static crop. Both off = neutral icon, both on = zebra wins.
    private var monitoringIcon: String {
        if controller.zebraEnabled { return "waveform.path.ecg.rectangle" }
        if controller.matteAspect > 0 { return "rectangle.split.3x1" }
        return "viewfinder"
    }
    private var monitoringActive: Bool {
        controller.zebraEnabled || controller.matteAspect > 0
    }

    private var zoomMenu: some View {
        Menu {
            ForEach(ZoomMode.allCases) { mode in
                Button {
                    controller.zoomMode = mode
                } label: {
                    if controller.zoomMode == mode {
                        Label(mode.label, systemImage: "checkmark")
                    } else {
                        Label(mode.label, systemImage: mode.icon)
                    }
                }
            }
            if controller.zoomMode == .actualSize,
               controller.videoNaturalSize != .zero {
                Divider()
                let s = controller.videoNaturalSize
                Text("Native: \(Int(s.width)) × \(Int(s.height))")
            }
        } label: {
            Image(systemName: controller.zoomMode.icon)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 36)
        .help("Zoom — Fit / Fill / Actual Size. Preview only; transcode keeps source dimensions.")
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

            // Loop toggle — orange when on. ⌘L from the menu bar.
            Button {
                controller.toggleLoop()
            } label: {
                Image(systemName: controller.loopMode
                                   ? "repeat.circle.fill" : "repeat")
                    .foregroundStyle(controller.loopMode ? Color.orange : Color.secondary)
            }
            .help("Loop mode (⌘L)")

            Button { controller.exportCurrentFrame() } label: {
                Image(systemName: "camera")
            }
            .help("Export current frame as PNG (⌘⇧E)")

            Button {
                NSApp.keyWindow?.toggleFullScreen(nil)
            } label: {
                Image(systemName: "rectangle.expand.vertical")
            }
            .help("Toggle fullscreen (⌘F)")

            zoomMenu
            monitoringMenu
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
        case "j":
            if jlMode == "jump5s" { controller.jumpSeconds(-5) }
            else                  { controller.shuttle(direction: -1) }
            return true
        case "k": controller.setRate(0); return true
        case "l":
            if jlMode == "jump5s" { controller.jumpSeconds(5) }
            else                  { controller.shuttle(direction: 1) }
            return true
        case "i": controller.markIn();               return true
        case "o": controller.markOut();              return true
        case "m": onAddMarker();                     return true
        case "s":
            if controller.inMarker != nil && controller.outMarker != nil {
                onSaveSubclip(); return true
            }
            return false
        case "x":
            // Kyno-compat: X mutes/unmutes audio. Always-on binding
            // regardless of compatibility mode — it's a useful key
            // that doesn't collide with PurpleReel-native ones.
            controller.toggleMute()
            return true
        default: break
        }
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 123:                       // ←
            if shift { controller.jumpSeconds(-5) }
            else     { controller.step(frames: -1) }
            return true
        case 124:                       // →
            if shift { controller.jumpSeconds(5) }
            else     { controller.step(frames: 1) }
            return true
        case 126: onJumpMarker(-1); return true   // ↑ previous marker
        case 125: onJumpMarker(1);  return true   // ↓ next marker
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
