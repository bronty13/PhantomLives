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
    /// C17 — PurpleReel-DB markers attached to this source clip.
    /// Whatever subset falls inside the resolved trim range will be
    /// copied onto the combined timeline at the right offset; the
    /// rest are dropped. Default empty = nothing to carry across.
    var sourceMarkers: [Marker] = []
}

/// C19 — picks the target canvas size for a combined output. The
/// dominant case for doc shooters is "match the first clip", which
/// is what Combine has done since the C8 MVP and stays the default.
/// `.largestSource` is the right call for mixed-resolution sets where
/// the user wants none of the sources downscaled; `.explicit` is for
/// delivery specs ("must be 1920×1080") that the source set doesn't
/// naturally satisfy.
enum CombineDimensionMode: Equatable {
    case firstClip
    case largestSource
    case explicit(width: Int, height: Int)
}

/// C17 — value-type description of one marker that survived the
/// trim/offset pass and should land on the combined output. Carries
/// timecode + note only; no `assetId` yet (the output asset is
/// rescanned-into-existence after export) and no GRDB conformance
/// (no rowid to round-trip). The sheet converts these into real
/// `Marker` rows once it has the new asset's id.
struct PreservedMarker: Equatable {
    var timecodeIn: Double
    var timecodeOut: Double?
    var note: String?
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
    /// C19 — canvas-size policy for the combined output. Default
    /// stays `.firstClip` so existing callers keep behaving the same.
    let dimensionMode: CombineDimensionMode

    @Published var state: State = .queued
    @Published var progress: Double = 0
    /// C17 — markers (filtered + offset) that should land on the
    /// combined output. Populated during the source-loop pass; the
    /// sheet writes them to DB after the export succeeds and the
    /// output asset has been catalogued.
    @Published var preservedMarkers: [PreservedMarker] = []

    private var exportSession: AVAssetExportSession?
    private var progressTimer: Timer?

    init(sources: [CombineSource], outputURL: URL, preset: TranscodePreset,
         dimensionMode: CombineDimensionMode = .firstClip) {
        self.sources = sources
        self.outputURL = outputURL
        self.preset = preset
        self.dimensionMode = dimensionMode
    }

    /// Convenience init for the pre-C16 URL-only call sites. Wraps
    /// each URL into a `CombineSource` with no trim — same behavior
    /// as before. Kept so non-dialog callers (workflow chains,
    /// scripted invocations) don't have to migrate at the same time.
    /// C19 — defaults `dimensionMode` to `.firstClip` so legacy
    /// callers keep producing the same output.
    convenience init(sources: [URL], outputURL: URL, preset: TranscodePreset,
                     dimensionMode: CombineDimensionMode = .firstClip) {
        self.init(
            sources: sources.map { CombineSource(url: $0) },
            outputURL: outputURL, preset: preset,
            dimensionMode: dimensionMode
        )
    }

    /// C19 — pure helper that resolves the target canvas size for
    /// the combined output given the picked policy and the natural
    /// sizes of the source clips (in render order). Returns nil if
    /// the policy can't be satisfied (e.g. `.firstClip` with an
    /// empty source list — caller falls back to leaving
    /// `comp.naturalSize` at its default).
    ///
    /// `.largestSource` picks the max width and max height
    /// independently — so a 1920×1080 source mixed with a
    /// 1080×1920 vertical one yields a 1920×1920 square canvas
    /// that pillarboxes BOTH (the wide one is letterboxed top/bottom
    /// to the square, the tall one is pillarboxed left/right). That
    /// preserves all pixels at the cost of black bars, which is
    /// the right default for a "don't downscale anything" policy.
    nonisolated static func resolveTargetSize(
        mode: CombineDimensionMode,
        sourceSizes: [CGSize]
    ) -> CGSize? {
        switch mode {
        case .firstClip:
            return sourceSizes.first
        case .largestSource:
            guard !sourceSizes.isEmpty else { return nil }
            let maxW = sourceSizes.map(\.width).max() ?? 0
            let maxH = sourceSizes.map(\.height).max() ?? 0
            guard maxW > 0, maxH > 0 else { return nil }
            return CGSize(width: maxW, height: maxH)
        case .explicit(let w, let h):
            guard w > 0, h > 0 else { return nil }
            return CGSize(width: w, height: h)
        }
    }

    /// C17 — pure offset/filter helper, extracted so the marker
    /// preservation rules are testable without spinning up
    /// `AVAssetExportSession`. Given a source's markers and its
    /// resolved trim range, returns the subset that falls inside
    /// the range (timecodeIn anywhere within [inSec, outSec]),
    /// shifted so they land at `cursorSec + (originalTC - inSec)`
    /// on the combined timeline.
    ///
    /// - `timecodeOut` is clamped to the trim window: a marker that
    ///   ends past `outSec` is truncated to the window's end so the
    ///   output doesn't carry a marker pointing beyond the combined
    ///   timeline's natural duration.
    /// - The note is left untouched. Provenance ("from clipA.mov")
    ///   is the sheet's call, not the service's — the service
    ///   doesn't know the source's filename in a way that's stable
    ///   across calls.
    nonisolated static func offsetMarkers(_ markers: [Marker],
                                          trimInSec: Double,
                                          trimOutSec: Double,
                                          cursorSec: Double) -> [PreservedMarker] {
        guard trimOutSec > trimInSec else { return [] }
        return markers.compactMap { m -> PreservedMarker? in
            guard m.timecodeIn >= trimInSec, m.timecodeIn <= trimOutSec else {
                return nil
            }
            let shiftedIn = cursorSec + (m.timecodeIn - trimInSec)
            let shiftedOut: Double? = m.timecodeOut.map { rawOut in
                let clamped = min(rawOut, trimOutSec)
                return cursorSec + (clamped - trimInSec)
            }
            return PreservedMarker(
                timecodeIn: shiftedIn,
                timecodeOut: shiftedOut,
                note: m.note
            )
        }
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
        // each source is inserted at the running cursor. C18 — for
        // audio-only output we skip the video track entirely so the
        // export session doesn't try to encode video into an m4a
        // container (it'd fail with "no compatible video").
        let comp = AVMutableComposition()
        let vTrack: AVMutableCompositionTrack? = preset.isAudioOnly ? nil
            : comp.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid)
        guard let aTrack = comp.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            state = .failed("Couldn't create composition tracks")
            return
        }
        if !preset.isAudioOnly && vTrack == nil {
            state = .failed("Couldn't create composition tracks")
            return
        }

        var cursor: CMTime = .zero
        var collectedMarkers: [PreservedMarker] = []
        // C19 — collect per-source natural sizes so we can resolve
        // the target canvas size after the loop. Audio-only outputs
        // skip the lookup (no video tracks to read), but it's cheap
        // to keep the code path uniform.
        var sourceSizes: [CGSize] = []
        var firstVideoTransform: CGAffineTransform?
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
                let aSources = try await asset.loadTracks(withMediaType: .audio)
                if let vTrack {
                    let vSources = try await asset.loadTracks(withMediaType: .video)
                    if let v = vSources.first {
                        try vTrack.insertTimeRange(range, of: v, at: cursor)
                        // C19 — record natural size for each video
                        // source so we can pick a target canvas
                        // after the loop. naturalSize is the encoded
                        // dimensions (not the preferredTransform-
                        // applied display size), which is what
                        // `comp.naturalSize` expects.
                        if let size = try? await v.load(.naturalSize) {
                            sourceSizes.append(size)
                        }
                        if firstVideoTransform == nil,
                           let xform = try? await v.load(.preferredTransform) {
                            firstVideoTransform = xform
                        }
                    }
                }
                if let a = aSources.first {
                    try aTrack.insertTimeRange(range, of: a, at: cursor)
                }
                // C17 — copy this source's markers onto the
                // combined timeline. cursor is captured *before* we
                // advance it for this clip, so it points at the
                // segment's start in the output.
                let preserved = Self.offsetMarkers(
                    source.sourceMarkers,
                    trimInSec: inSec,
                    trimOutSec: outSec,
                    cursorSec: CMTimeGetSeconds(cursor)
                )
                collectedMarkers.append(contentsOf: preserved)
                cursor = CMTimeAdd(cursor, dur)
            } catch {
                state = .failed("Couldn't read \(url.lastPathComponent): \(error.localizedDescription)")
                return
            }
        }
        // Publish the collected markers now so the sheet can see
        // them as soon as the loop has run, even before the export
        // session finishes. (The sheet still gates the DB write on
        // .finished — published-early just helps the UI badge.)
        preservedMarkers = collectedMarkers

        // C19 — pick the target canvas size from the chosen policy.
        // Default `.firstClip` keeps pre-C19 behavior (canvas matches
        // the first clip's natural size). `.largestSource` widens to
        // the union of source dimensions; `.explicit` clamps to the
        // user-specified WxH. Skipped on audio-only — no video track.
        if let vTrack,
           let target = Self.resolveTargetSize(mode: dimensionMode,
                                                sourceSizes: sourceSizes) {
            comp.naturalSize = target
            if let xform = firstVideoTransform {
                vTrack.preferredTransform = xform
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
    /// audio-only m4a wants `.m4a`, H.264 / HEVC are happy in `.mp4`.
    private func containerType() -> AVFileType {
        switch preset.avPresetName {
        case AVAssetExportPresetAppleProRes422LPCM,
             AVAssetExportPresetAppleProRes4444LPCM:
            return .mov
        case AVAssetExportPresetAppleM4A:
            return .m4a
        default:
            return .mp4
        }
    }
}
