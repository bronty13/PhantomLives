import Foundation
import AVFoundation
import AppKit

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

    @Published var state: State = .queued
    @Published var progress: Double = 0

    private var exportSession: AVAssetExportSession?
    private var progressTimer: Timer?

    init(source: URL, preset: TranscodePreset, outputURL: URL,
         fadeInSeconds: Double = 0, fadeOutSeconds: Double = 0) {
        self.source = source
        self.preset = preset
        self.outputURL = outputURL
        self.fadeInSeconds = max(0, fadeInSeconds)
        self.fadeOutSeconds = max(0, fadeOutSeconds)
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

        // Audio + video fades (Kyno 1.6 parity). Skipped for the
        // pass-through preset — the export bypasses both audioMix
        // and videoComposition when re-wrapping the source. Built
        // from the source AVAsset's tracks directly; no full
        // composition needed because AVAssetExportSession accepts
        // these on top of the bare asset.
        if (fadeInSeconds > 0 || fadeOutSeconds > 0)
           && preset.avPresetName != AVAssetExportPresetPassthrough {
            await applyFades(to: session, asset: asset)
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

    /// Build audio-volume ramps and a video opacity-ramp composition
    /// for the requested fade-in / fade-out durations, and hang them
    /// off the export session. Black background for the video fades
    /// (the composition's default render color is `.clear`, which
    /// would composite the source over nothing — visually identical
    /// to fade-to-black at the start/end where there's no source).
    private func applyFades(to session: AVAssetExportSession,
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
        if let videoTracks = try? await asset.loadTracks(withMediaType: .video),
           let videoTrack = videoTracks.first {
            let comp = AVMutableVideoComposition()
            // Use the source track's nominal frame rate when sane,
            // otherwise 30 fps — Apple's HEIC/PNG fallback.
            let nominal = (try? await videoTrack.load(.nominalFrameRate)) ?? 30
            let fr = nominal > 0 ? Double(nominal) : 30
            comp.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fr.rounded()))
            // Honor any preferred transform / native size on the
            // source so the export doesn't end up rotated.
            let natural = (try? await videoTrack.load(.naturalSize)) ?? .zero
            let transform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
            let rotated = natural.applying(transform)
            comp.renderSize = CGSize(
                width: abs(rotated.width), height: abs(rotated.height)
            )

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
