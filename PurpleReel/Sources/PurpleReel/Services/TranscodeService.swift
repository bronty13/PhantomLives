import Foundation
import AVFoundation
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// A single transcode job. State is observable so views can show
/// per-row progress without diffing through a parent queue.
@MainActor
final class TranscodeJob: ObservableObject, Identifiable {
    enum State: Equatable {
        case queued
        case running
        case finished(URL)
        case failed(String)
        case cancelled

        var isTerminal: Bool {
            switch self {
            case .finished, .failed, .cancelled: return true
            default: return false
            }
        }
    }

    let id = UUID()
    let source: URL
    let preset: TranscodePreset
    let outputURL: URL
    /// Fade-in / fade-out durations in seconds. Zero = off.
    /// Applied via `AVMutableAudioMix` + `AVMutableVideoComposition`
    /// in the AVFoundation export path; ignored on ffmpeg presets
    /// (filter-chain merge is a follow-up).
    let fadeInSeconds: Double
    let fadeOutSeconds: Double
    /// Burn the running source timecode into every output frame.
    /// AVFoundation-only; honored alongside fades by composing the
    /// opacity ramp into a single CIFilter-handler videoComposition.
    let tcBurnIn: Bool

    @Published var state: State = .queued
    @Published var progress: Double = 0

    private var exportSession: AVAssetExportSession?
    private var progressTimer: Timer?

    init(source: URL, preset: TranscodePreset, outputURL: URL,
         fadeInSeconds: Double = 0, fadeOutSeconds: Double = 0,
         tcBurnIn: Bool = false) {
        self.source = source
        self.preset = preset
        self.outputURL = outputURL
        self.fadeInSeconds = max(0, fadeInSeconds)
        self.fadeOutSeconds = max(0, fadeOutSeconds)
        self.tcBurnIn = tcBurnIn
    }

    /// Composable initializer (C3). Builds a synthetic
    /// `TranscodePreset` from the resolved backend so the existing
    /// AVAssetExportSession / ffmpeg branch + progress polling +
    /// cancellation flow downstream unchanged. The synthetic preset
    /// is never persisted — it's a one-shot adapter from the new
    /// composable `TranscodeOptions` shape to today's runner.
    ///
    /// `displayName` lands on the synthetic preset's `name` so the
    /// queue UI shows something meaningful instead of an opaque
    /// "options-<uuid>". `category` defaults to `.editing` because
    /// the composable Convert dialog doesn't push category back into
    /// the model — but the queue UI doesn't currently render it.
    convenience init(source: URL, options: TranscodeOptions,
                     outputURL: URL, displayName: String = "Custom",
                     fadeInSeconds: Double = 0,
                     fadeOutSeconds: Double = 0,
                     tcBurnIn: Bool = false) {
        let backend = options.resolveBackend()
        let synthetic: TranscodePreset
        switch backend {
        case .avAssetExport(let presetName, let ext, let alwaysAvailable):
            synthetic = TranscodePreset(
                id: "options-\(UUID().uuidString)",
                name: displayName,
                avPresetName: presetName,
                fileExtension: ext,
                suffix: "_custom",
                category: .editing,
                alwaysAvailable: alwaysAvailable,
                ffmpegArgs: nil
            )
        case .ffmpeg(let args, let ext):
            synthetic = TranscodePreset(
                id: "options-\(UUID().uuidString)",
                name: displayName,
                avPresetName: "",
                fileExtension: ext,
                suffix: "_custom",
                category: .editing,
                alwaysAvailable: true,
                ffmpegArgs: args
            )
        }
        self.init(source: source, preset: synthetic, outputURL: outputURL,
                  fadeInSeconds: fadeInSeconds,
                  fadeOutSeconds: fadeOutSeconds,
                  tcBurnIn: tcBurnIn)
    }

    func run() async {
        state = .running
        progress = 0

        // ffmpeg-routed presets go through a separate pipeline: we
        // shell out to /usr/bin/env ffmpeg with the recipe's argument
        // template, substituting {IN} / {OUT}.
        if preset.isFFmpeg {
            await runFFmpeg()
            return
        }

        let asset = AVURLAsset(url: source)

        // Some presets are codec-restricted (H.264 / HEVC) and need
        // gating against the input asset; ProRes / pass-through are
        // always available.
        if !preset.alwaysAvailable {
            let compatible = await AVAssetExportSession.compatibility(
                ofExportPreset: preset.avPresetName,
                with: asset, outputFileType: containerType()
            )
            if !compatible {
                state = .failed("Preset \(preset.name) not compatible with source")
                return
            }
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: preset.avPresetName) else {
            state = .failed("Could not create export session")
            return
        }
        session.outputURL = outputURL
        session.outputFileType = containerType()
        session.shouldOptimizeForNetworkUse = true
        self.exportSession = session

        // Audio + video fades + optional timecode burn-in.
        // Skipped for the pass-through preset — the export bypasses
        // both audioMix and videoComposition when re-wrapping the
        // source. Built from the source AVAsset's tracks directly;
        // no full composition needed because AVAssetExportSession
        // accepts both on top of the bare asset.
        let needsComposition = fadeInSeconds > 0
            || fadeOutSeconds > 0
            || tcBurnIn
        if needsComposition
           && preset.avPresetName != AVAssetExportPresetPassthrough {
            await applyComposition(to: session, asset: asset)
        }

        try? FileManager.default.removeItem(at: outputURL)
        try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                                  withIntermediateDirectories: true)

        // AVAssetExportSession.progress is updated on its own thread;
        // poll it on a timer for SwiftUI publishing.
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.progress = Double(self.exportSession?.progress ?? 0)
            }
        }
        defer {
            progressTimer?.invalidate()
            progressTimer = nil
        }

        await session.export()

        switch session.status {
        case .completed:
            progress = 1
            preserveTimestampsIfRequested()
            state = .finished(outputURL)
        case .cancelled:
            state = .cancelled
        case .failed:
            state = .failed(session.error?.localizedDescription ?? "Unknown export failure")
        default:
            state = .failed("Export ended in unexpected state \(session.status.rawValue)")
        }
    }

    /// Build the export-side composition: audio volume ramps for the
    /// requested fade-in / fade-out durations, plus a video pipeline
    /// that handles either layer-instruction-driven opacity ramps
    /// (when TC burn-in is off — cheap, no per-frame work) OR a
    /// CIFilter-handler that does both opacity multiplication and
    /// per-frame timecode rendering (when TC burn-in is on).
    private func applyComposition(to session: AVAssetExportSession,
                                    asset: AVURLAsset) async {
        let duration = (try? await asset.load(.duration)) ?? .zero
        let durSec = CMTimeGetSeconds(duration)
        guard durSec.isFinite, durSec > 0 else { return }
        let inLen = min(fadeInSeconds, durSec)
        let outLen = min(fadeOutSeconds, durSec)

        // ----- audio ----------------------------------------------
        if let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
           !audioTracks.isEmpty {
            let audioMix = AVMutableAudioMix()
            var params: [AVMutableAudioMixInputParameters] = []
            for track in audioTracks {
                let p = AVMutableAudioMixInputParameters(track: track)
                if inLen > 0 {
                    let endTime = CMTime(seconds: inLen, preferredTimescale: 600)
                    p.setVolumeRamp(
                        fromStartVolume: 0,
                        toEndVolume: 1,
                        timeRange: CMTimeRange(start: .zero, end: endTime)
                    )
                }
                if outLen > 0 {
                    let startSec = max(0, durSec - outLen)
                    let outStart = CMTime(seconds: startSec, preferredTimescale: 600)
                    p.setVolumeRamp(
                        fromStartVolume: 1,
                        toEndVolume: 0,
                        timeRange: CMTimeRange(start: outStart, end: duration)
                    )
                }
                params.append(p)
            }
            audioMix.inputParameters = params
            session.audioMix = audioMix
        }

        // ----- video ----------------------------------------------
        // Two pipelines:
        //  - When TC burn-in is off, opacity ramps via the lighter
        //    layer-instruction path. Zero per-frame cost.
        //  - When TC burn-in is on, switch to a CIFilter handler
        //    that does opacity multiplication AND text rendering
        //    inside one closure. The handler approach is the only
        //    way AVFoundation lets us draw arbitrary content per
        //    frame from CoreImage.
        guard let videoTracks = try? await asset.loadTracks(withMediaType: .video),
              let videoTrack = videoTracks.first else { return }

        let nominal = (try? await videoTrack.load(.nominalFrameRate)) ?? 30
        let trackFps = Double(nominal > 0 ? nominal : 30)
        let natural = (try? await videoTrack.load(.naturalSize)) ?? .zero
        let transform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
        let rotated = natural.applying(transform)
        let renderSize = CGSize(
            width: abs(rotated.width), height: abs(rotated.height)
        )

        if tcBurnIn {
            let comp = AVMutableVideoComposition(
                asset: asset,
                applyingCIFiltersWithHandler: { [inLen, outLen, durSec] request in
                    var image = request.sourceImage
                    let t = CMTimeGetSeconds(request.compositionTime)

                    // Opacity ramp (fade in/out), computed on the
                    // request time. Multiplied into alpha via a
                    // CIColorMatrix because CIImage has no direct
                    // opacity setter on the input side.
                    var alpha = 1.0
                    if inLen > 0, t < inLen {
                        alpha = max(0, t / inLen)
                    }
                    if outLen > 0 {
                        let outStartT = durSec - outLen
                        if t > outStartT {
                            alpha = min(alpha, max(0, (durSec - t) / outLen))
                        }
                    }
                    if alpha < 1 {
                        let mat = CIFilter.colorMatrix()
                        mat.inputImage = image
                        mat.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
                        mat.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
                        mat.bVector = CIVector(x: 0, y: 0, z: 1, w: 0)
                        mat.aVector = CIVector(x: 0, y: 0, z: 0,
                                                 w: CGFloat(alpha))
                        image = mat.outputImage ?? image
                    }

                    // TC overlay — drawn at the source extent so
                    // the position math is in pixel coordinates of
                    // the un-rotated frame. AVFoundation applies
                    // the track's preferredTransform after our
                    // handler returns, so we don't need to rotate.
                    let extent = request.sourceImage.extent
                    let label = Timecode.format(seconds: t, fps: trackFps)
                    let tcImage = Self.makeTCOverlay(
                        text: label, frameSize: extent.size
                    )
                    let over = CIFilter.sourceOverCompositing()
                    over.inputImage = tcImage
                    over.backgroundImage = image
                    let composed = over.outputImage ?? image
                    request.finish(
                        with: composed.cropped(to: extent),
                        context: nil
                    )
                }
            )
            session.videoComposition = comp
            return
        }

        // Fade-only path (no TC burn-in): layer-instruction
        // opacity ramps. Cheaper because there's no per-frame
        // CIFilter dispatch.
        let comp = AVMutableVideoComposition()
        comp.frameDuration = CMTime(
            value: 1, timescale: CMTimeScale(trackFps.rounded())
        )
        comp.renderSize = renderSize

        let inst = AVMutableVideoCompositionInstruction()
        inst.timeRange = CMTimeRange(start: .zero, duration: duration)
        inst.backgroundColor = NSColor.black.cgColor

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layer.setTransform(transform, at: .zero)
        if inLen > 0 {
            let endTime = CMTime(seconds: inLen, preferredTimescale: 600)
            layer.setOpacityRamp(
                fromStartOpacity: 0,
                toEndOpacity: 1,
                timeRange: CMTimeRange(start: .zero, end: endTime)
            )
        }
        if outLen > 0 {
            let startSec = max(0, durSec - outLen)
            let outStart = CMTime(seconds: startSec, preferredTimescale: 600)
            layer.setOpacityRamp(
                fromStartOpacity: 1,
                toEndOpacity: 0,
                timeRange: CMTimeRange(start: outStart, end: duration)
            )
        }
        inst.layerInstructions = [layer]
        comp.instructions = [inst]
        session.videoComposition = comp
    }

    /// Render the TC label into a small CGContext sized to the text
    /// box, then position it bottom-center of `frameSize` as a
    /// transparent-background CIImage. We render only the box (not
    /// a full-frame canvas) to keep per-frame allocations small;
    /// AVAssetExportSession dispatches dozens of these per second
    /// of video.
    nonisolated static func makeTCOverlay(text: String,
                                            frameSize: CGSize) -> CIImage {
        // Defensive guards (added after a 2026-05-18 crash on a
        // clip whose source-image extent came through with a
        // non-finite width — `Int(boxWidth)` then trapped with
        // "Double value cannot be converted to Int because the
        // result would be greater than Int.max"). AVFoundation can
        // hand us empty / null extents during transitions or for
        // partially-loaded items; we should silently no-op
        // instead of crashing the transcode session.
        guard frameSize.width.isFinite,
              frameSize.height.isFinite,
              frameSize.width > 0,
              frameSize.height > 0
        else { return CIImage.empty() }
        // Clamp font size into a sane range so an absurd frame
        // size (e.g. 50000-wide composition) can't escape into
        // `attrStr.size()` returning out-of-range values.
        let rawFont = frameSize.width * 0.04
        let fontSize = max(20, min(rawFont.isFinite ? rawFont : 20, 200))
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrStr.size()
        guard textSize.width.isFinite, textSize.height.isFinite,
              textSize.width > 0, textSize.height > 0
        else { return CIImage.empty() }
        let pad: CGFloat = max(8, fontSize * 0.3)
        // Cap at a reasonable max so a degenerate font / glyph set
        // can't produce a multi-million-pixel context.
        let boxWidth  = min(ceil(textSize.width + pad * 2), 4096)
        let boxHeight = min(ceil(textSize.height + pad * 2), 512)
        let bytesPerRow = Int(boxWidth) * 4
        guard let ctx = CGContext(
            data: nil,
            width: Int(boxWidth),
            height: Int(boxHeight),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return CIImage.empty() }
        ctx.clear(CGRect(x: 0, y: 0, width: boxWidth, height: boxHeight))
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.65))
        ctx.fill(CGRect(x: 0, y: 0, width: boxWidth, height: boxHeight))
        // NSAttributedString.draw needs an NSGraphicsContext on the
        // stack. Restore the previous one when we're done — the
        // export session uses CoreGraphics from multiple threads
        // and we don't want to leak the wrapper.
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        attrStr.draw(at: CGPoint(x: pad, y: pad))
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = ctx.makeImage() else { return CIImage.empty() }
        let img = CIImage(cgImage: cg)
        // Position bottom-center. CIImage uses bottom-left origin;
        // 30px above the bottom keeps the badge clear of the
        // safe-area mask most monitors will overlay anyway.
        let x = (frameSize.width - boxWidth) / 2
        let y: CGFloat = max(20, frameSize.height * 0.04)
        return img.transformed(by: CGAffineTransform(translationX: x, y: y))
    }

    /// Optionally copy the source file's mtime onto the freshly-
    /// written output. Toggled by `preserveTranscodeTimestamps` in
    /// Settings → Conversion; off by default so the user sees
    /// "modified just now" for freshly-rendered exports (matches
    /// AVAssetExportSession's default behavior). Kyno 1.2 shipped
    /// this for archival workflows where timestamps key the chain
    /// of custody.
    private nonisolated func preserveTimestampsIfRequested() {
        guard UserDefaults.standard.bool(forKey: "preserveTranscodeTimestamps")
        else { return }
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: source.path),
              let mtime = attrs[.modificationDate] as? Date else { return }
        try? fm.setAttributes([.modificationDate: mtime],
                               ofItemAtPath: outputURL.path)
    }

    func cancel() {
        exportSession?.cancelExport()
    }

    private func containerType() -> AVFileType {
        switch preset.fileExtension.lowercased() {
        case "mp4", "m4v": return .mp4
        case "mov": return .mov
        default: return .mov
        }
    }

    /// ffmpeg shell-out path for Phase-2 codecs (DNxHR, Cineform,
    /// MXF rewrap). Parses ffmpeg's `time=HH:MM:SS.ss` lines from
    /// stderr to drive the progress bar.
    private func runFFmpeg() async {
        guard let recipe = preset.ffmpegArgs else {
            state = .failed("Preset has no ffmpeg recipe"); return
        }
        guard let ffmpeg = findFFmpegExecutable() else {
            state = .failed(
                "ffmpeg not found. Install with `brew install ffmpeg` and rerun."
            )
            return
        }

        try? FileManager.default.removeItem(at: outputURL)
        try? FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let args = recipe.map { arg in
            arg.replacingOccurrences(of: "{IN}", with: source.path)
               .replacingOccurrences(of: "{OUT}", with: outputURL.path)
        }

        // Probe input duration so the `time=` parser can produce
        // a 0…1 progress fraction.
        let sourceDuration = CMTimeGetSeconds(
            (try? await AVURLAsset(url: source).load(.duration)) ?? .zero
        )
        let totalSeconds = max(0.1, sourceDuration.isFinite ? sourceDuration : 0)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: ffmpeg)
        task.arguments = args
        let pipe = Pipe()
        task.standardError = pipe   // ffmpeg writes progress to stderr
        task.standardOutput = Pipe()  // drop stdout

        do { try task.run() } catch {
            state = .failed("Could not launch ffmpeg: \(error.localizedDescription)")
            return
        }

        let handle = pipe.fileHandleForReading
        let durSeconds = totalSeconds
        handle.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            if data.isEmpty {
                fh.readabilityHandler = nil
                return
            }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            // ffmpeg progress lines look like:
            //   frame= 1234 fps=… time=00:00:42.50 bitrate=… speed=…
            // Parse the time= occurrences and update progress.
            if let timeRange = chunk.range(of: "time=") {
                let after = chunk[timeRange.upperBound...]
                let token = after.prefix { !$0.isWhitespace }
                if let secs = Self.parseFFmpegTime(String(token)) {
                    let frac = min(1.0, secs / durSeconds)
                    Task { @MainActor in self?.progress = frac }
                }
            }
        }

        // Wait off the main actor.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            task.terminationHandler = { _ in cont.resume() }
        }

        if task.terminationStatus == 0 {
            progress = 1.0
            preserveTimestampsIfRequested()
            state = .finished(outputURL)
        } else {
            state = .failed("ffmpeg exited \(task.terminationStatus)")
        }
    }

    private func findFFmpegExecutable() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Parse `HH:MM:SS.xx` → seconds. Returns nil on malformed input.
    /// Called from the ffmpeg-stderr readability handler (background
    /// queue), so it must NOT be main-actor isolated.
    nonisolated static func parseFFmpegTime(_ s: String) -> Double? {
        let parts = s.split(separator: ":")
        guard parts.count == 3 else { return nil }
        guard let h = Double(parts[0]),
              let m = Double(parts[1]),
              let sec = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + sec
    }
}

enum TranscodeService {
    /// Default output directory per PhantomLives convention:
    /// `~/Downloads/PurpleReel/transcoded/`.
    static func defaultOutputDirectory() throws -> URL {
        let downloads = try FileManager.default.url(for: .downloadsDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
        let dir = downloads.appendingPathComponent("PurpleReel/transcoded", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Build the canonical output URL for a given source + preset.
    /// Collisions are resolved with a numeric suffix.
    static func outputURL(for source: URL, preset: TranscodePreset,
                          in directory: URL) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent(
            "\(base)\(preset.suffix).\(preset.fileExtension)"
        )
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent(
                "\(base)\(preset.suffix)_\(counter).\(preset.fileExtension)"
            )
            counter += 1
        }
        return candidate
    }
}
