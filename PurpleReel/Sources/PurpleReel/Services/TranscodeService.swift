import Foundation
import AVFoundation

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

    @Published var state: State = .queued
    @Published var progress: Double = 0

    private var exportSession: AVAssetExportSession?
    private var progressTimer: Timer?

    init(source: URL, preset: TranscodePreset, outputURL: URL) {
        self.source = source
        self.preset = preset
        self.outputURL = outputURL
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
