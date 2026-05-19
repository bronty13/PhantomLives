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

    @Published var state: State = .queued
    @Published var progress: Double = 0
    /// C17 — markers (filtered + offset) that should land on the
    /// combined output. Populated during the source-loop pass; the
    /// sheet writes them to DB after the export succeeds and the
    /// output asset has been catalogued.
    @Published var preservedMarkers: [PreservedMarker] = []

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
        var collectedMarkers: [PreservedMarker] = []
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
