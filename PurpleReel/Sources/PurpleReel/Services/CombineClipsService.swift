import Foundation
import AVFoundation

/// One source row for `CombineClipsJob`. Carries the URL plus
/// optional in/out trim points (seconds from clip start). Both nil
/// = whole-clip concat, matching the C8 MVP behavior; setting either
/// trims that side of the range. C16 follow-up.
struct CombineSource: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    /// Seconds from clip start. nil = clip's natural start (0).
    var trimInSeconds: Double?
    /// Seconds from clip start. nil = clip's natural end (duration).
    var trimOutSeconds: Double?
}

/// "Combine clips" — Kyno-parity row 8. Builds an
/// `AVMutableComposition` from the supplied source URLs in order
/// and renders it through `AVAssetExportSession` into a single
/// `.mov` / `.mp4` so doc shooters can glue several talking-head
/// pieces together without spinning up Final Cut.
///
/// Scope (C16):
///   - Per-clip in/out trim honored via `CombineSource.trimIn/Out`.
///     nil on both sides = whole-clip concat (the pre-C16 MVP path).
///   - No transitions. Cuts only — matches Kyno's release-note
///     framing ("Combine multiple clips into one"). Cross-fades
///     are a separate follow-up.
///   - First clip's natural video size wins. Mixed-resolution sets
///     emerge with the first clip's frame size; the rest get
///     letterboxed by the export session's preset.
@MainActor
final class CombineClipsJob: ObservableObject, Identifiable {
    enum State: Equatable {
        case queued, running
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
    let sources: [CombineSource]
    let outputURL: URL
    let preset: TranscodePreset

    @Published var state: State = .queued
    @Published var progress: Double = 0

    private var exportSession: AVAssetExportSession?
    private var progressTimer: Timer?

    init(sources: [CombineSource], outputURL: URL, preset: TranscodePreset) {
        self.sources = sources
        self.outputURL = outputURL
        self.preset = preset
    }

    /// Convenience init for the pre-C16 URL-only call sites. Wraps
    /// each URL into a `CombineSource` with no trim — same behavior
    /// as before. Kept so non-dialog callers (workflow chains,
    /// scripted invocations) don't have to migrate at the same time.
    convenience init(sources: [URL], outputURL: URL, preset: TranscodePreset) {
        self.init(
            sources: sources.map { CombineSource(url: $0) },
            outputURL: outputURL, preset: preset
        )
    }

    func cancel() {
        exportSession?.cancelExport()
        state = .cancelled
        progressTimer?.invalidate()
        progressTimer = nil
    }

    func run() async {
        state = .running
        progress = 0

        // Build the head-to-tail composition. Tracks are added once;
        // each source is inserted at the running cursor.
        let comp = AVMutableComposition()
        guard let vTrack = comp.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid),
              let aTrack = comp.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            state = .failed("Couldn't create composition tracks")
            return
        }

        var cursor: CMTime = .zero
        for source in sources {
            let url = source.url
            let asset = AVURLAsset(url: url)
            do {
                let assetDuration = try await asset.load(.duration)
                // Resolve trim points → CMTimeRange against the
                // asset's natural timeline. Clamp to the asset's
                // actual duration so an out-of-bounds trimOut just
                // takes us to the end rather than failing.
                let durSeconds = CMTimeGetSeconds(assetDuration)
                let inSec = source.trimInSeconds.map {
                    max(0, min($0, durSeconds))
                } ?? 0
                let outSec = source.trimOutSeconds.map {
                    max(0, min($0, durSeconds))
                } ?? durSeconds
                let trimmedSeconds = max(0, outSec - inSec)
                if trimmedSeconds <= 0 {
                    state = .failed("\(url.lastPathComponent) has an empty trim range (\(inSec)s → \(outSec)s).")
                    return
                }
                let start = CMTime(seconds: inSec,
                                    preferredTimescale: assetDuration.timescale)
                let dur = CMTime(seconds: trimmedSeconds,
                                  preferredTimescale: assetDuration.timescale)
                let range = CMTimeRange(start: start, duration: dur)
                let vSources = try await asset.loadTracks(withMediaType: .video)
                let aSources = try await asset.loadTracks(withMediaType: .audio)
                if let v = vSources.first {
                    try vTrack.insertTimeRange(range, of: v, at: cursor)
                }
                if let a = aSources.first {
                    try aTrack.insertTimeRange(range, of: a, at: cursor)
                }
                cursor = CMTimeAdd(cursor, dur)
            } catch {
                state = .failed("Couldn't read \(url.lastPathComponent): \(error.localizedDescription)")
                return
            }
        }

        // Pick a sensible orientation for the output composition. We
        // copy the first video source's `preferredTransform` so the
        // composition rotates portrait phone footage right-side-up.
        if let firstSource = sources.first {
            let firstAsset = AVURLAsset(url: firstSource.url)
            if let firstV = try? await firstAsset.loadTracks(withMediaType: .video).first,
               let xform = try? await firstV.load(.preferredTransform),
               let size = try? await firstV.load(.naturalSize) {
                vTrack.preferredTransform = xform
                comp.naturalSize = size
            }
        }

        // Pre-create the destination directory and clobber any prior
        // partial output so AVAssetExportSession doesn't fail with
        // "file exists".
        try? FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: outputURL)

        guard let session = AVAssetExportSession(
            asset: comp, presetName: preset.avPresetName
        ) else {
            state = .failed("Couldn't create export session for preset \(preset.name)")
            return
        }
        session.outputURL = outputURL
        session.outputFileType = containerType()
        session.shouldOptimizeForNetworkUse = true
        self.exportSession = session

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
        case .failed:
            state = .failed(session.error?.localizedDescription ?? "Export failed")
            try? FileManager.default.removeItem(at: outputURL)
        case .cancelled:
            state = .cancelled
            try? FileManager.default.removeItem(at: outputURL)
        default:
            state = .failed("Export ended in unexpected state \(session.status.rawValue)")
        }
    }

    /// Match the file type to the chosen preset. ProRes wants `.mov`,
    /// H.264 / HEVC are happy in `.mp4`.
    private func containerType() -> AVFileType {
        switch preset.avPresetName {
        case AVAssetExportPresetAppleProRes422LPCM,
             AVAssetExportPresetAppleProRes4444LPCM:
            return .mov
        default:
            return .mp4
        }
    }
}
