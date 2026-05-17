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
            state = .finished(outputURL)
        case .cancelled:
            state = .cancelled
        case .failed:
            state = .failed(session.error?.localizedDescription ?? "Unknown export failure")
        default:
            state = .failed("Export ended in unexpected state \(session.status.rawValue)")
        }
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
