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
    /// C20 — global cross-fade duration in seconds. 0 = hard cut
    /// (pre-C20 behavior; takes the simpler single-track path).
    /// Anything > 0 takes the dual-track + AVMutableVideoComposition
    /// path with opacity & volume ramps. Clamped at run time so it
    /// can't exceed half of the shortest trimmed segment.
    let crossfadeSeconds: Double
    /// C23 — opacity / volume ramp from black/silence on the first
    /// clip's leading edge. 0 = no fade-in (default). Clamped to
    /// the first clip's trimmed duration. Triggers an
    /// AVMutableVideoComposition + AVMutableAudioMix even when
    /// `crossfadeSeconds == 0` so the edge ramp can land.
    let fadeFromBlackSeconds: Double
    /// C23 — symmetric trailing ramp on the last clip. Same rules.
    let fadeToBlackSeconds: Double

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
         dimensionMode: CombineDimensionMode = .firstClip,
         crossfadeSeconds: Double = 0,
         fadeFromBlackSeconds: Double = 0,
         fadeToBlackSeconds: Double = 0) {
        self.sources = sources
        self.outputURL = outputURL
        self.preset = preset
        self.dimensionMode = dimensionMode
        self.crossfadeSeconds = max(0, crossfadeSeconds)
        self.fadeFromBlackSeconds = max(0, fadeFromBlackSeconds)
        self.fadeToBlackSeconds = max(0, fadeToBlackSeconds)
    }

    /// Convenience init for the pre-C16 URL-only call sites. Wraps
    /// each URL into a `CombineSource` with no trim — same behavior
    /// as before. Kept so non-dialog callers (workflow chains,
    /// scripted invocations) don't have to migrate at the same time.
    /// Defaults all fade durations to 0 so legacy callers keep
    /// producing the same output.
    convenience init(sources: [URL], outputURL: URL, preset: TranscodePreset,
                     dimensionMode: CombineDimensionMode = .firstClip,
                     crossfadeSeconds: Double = 0,
                     fadeFromBlackSeconds: Double = 0,
                     fadeToBlackSeconds: Double = 0) {
        self.init(
            sources: sources.map { CombineSource(url: $0) },
            outputURL: outputURL, preset: preset,
            dimensionMode: dimensionMode,
            crossfadeSeconds: crossfadeSeconds,
            fadeFromBlackSeconds: fadeFromBlackSeconds,
            fadeToBlackSeconds: fadeToBlackSeconds
        )
    }

    /// C20 — pure helper that clamps the requested cross-fade so
    /// it can't exceed half of the shortest trimmed segment. Two
    /// neighbors with a 3-second cross-fade against a 4-second
    /// middle clip would consume 6 seconds of a 4-second source,
    /// leaving nothing in the middle (and the dual-track inserts
    /// would underflow). Half-of-shortest is the conservative
    /// rule that keeps every clip's solo region non-negative.
    ///
    /// `trimmedDurations` is in render order. Empty list (no
    /// sources) → 0. Single source → 0 (nothing to fade between).
    nonisolated static func clampCrossfadeSeconds(
        _ requested: Double,
        trimmedDurations: [Double]
    ) -> Double {
        guard requested > 0, trimmedDurations.count >= 2 else { return 0 }
        let shortest = trimmedDurations.min() ?? 0
        let maxAllowed = shortest / 2
        return max(0, min(requested, maxAllowed))
    }

    /// C23 — pure helper that clamps a fade-from-black or fade-to-
    /// black duration so it can't exceed the corresponding edge
    /// clip's trimmed duration. Symmetric on both sides of the
    /// timeline: leading-edge fade-in is bounded by the first clip's
    /// duration; trailing-edge fade-out is bounded by the last
    /// clip's. Returns 0 for empty input / negative request.
    nonisolated static func clampEdgeFadeSeconds(
        _ requested: Double,
        edgeClipDuration: Double
    ) -> Double {
        guard requested > 0, edgeClipDuration > 0 else { return 0 }
        return min(requested, edgeClipDuration)
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

        // C20 — phase 1: pre-resolve each source's trim metadata so
        // we know all trimmed durations *before* clamping the cross-
        // fade (clamp = half of shortest segment). The pre-pass only
        // touches `.duration`, not the heavier tracks load, so it's
        // cheap relative to the export itself.
        struct Resolved {
            let url: URL
            let trimRange: CMTimeRange
            let trimmedSeconds: Double
            let timescale: CMTimeScale
            let sourceMarkers: [Marker]
            let trimInSec: Double
            let trimOutSec: Double
        }
        var resolved: [Resolved] = []
        for source in sources {
            let asset = AVURLAsset(url: source.url)
            do {
                let assetDuration = try await asset.load(.duration)
                let durSeconds = CMTimeGetSeconds(assetDuration)
                let inSec = source.trimInSeconds.map { max(0, min($0, durSeconds)) } ?? 0
                let outSec = source.trimOutSeconds.map { max(0, min($0, durSeconds)) } ?? durSeconds
                let trimmedSeconds = max(0, outSec - inSec)
                if trimmedSeconds <= 0 {
                    state = .failed("\(source.url.lastPathComponent) has an empty trim range (\(inSec)s → \(outSec)s).")
                    return
                }
                let start = CMTime(seconds: inSec,
                                    preferredTimescale: assetDuration.timescale)
                let dur = CMTime(seconds: trimmedSeconds,
                                  preferredTimescale: assetDuration.timescale)
                resolved.append(Resolved(
                    url: source.url,
                    trimRange: CMTimeRange(start: start, duration: dur),
                    trimmedSeconds: trimmedSeconds,
                    timescale: assetDuration.timescale,
                    sourceMarkers: source.sourceMarkers,
                    trimInSec: inSec,
                    trimOutSec: outSec
                ))
            } catch {
                state = .failed("Couldn't read \(source.url.lastPathComponent): \(error.localizedDescription)")
                return
            }
        }

        // C20 — clamp the cross-fade against the trimmed durations.
        // useDual is the load-bearing branch — when true we allocate
        // two video / audio tracks and build an
        // AVMutableVideoComposition + AVMutableAudioMix for the
        // opacity & volume ramps.
        let clampedCF = Self.clampCrossfadeSeconds(
            crossfadeSeconds,
            trimmedDurations: resolved.map(\.trimmedSeconds)
        )
        let useDual = clampedCF > 0 && resolved.count >= 2
        // C23 — clamp edge fades against the first / last clip's
        // trimmed duration. fadeIn / fadeOut may be non-zero even
        // when cross-fade is zero; in that case we still build a
        // video composition + audio mix (single-track) for the
        // edge ramps.
        let firstDur = resolved.first?.trimmedSeconds ?? 0
        let lastDur = resolved.last?.trimmedSeconds ?? 0
        let clampedFadeIn = Self.clampEdgeFadeSeconds(
            fadeFromBlackSeconds, edgeClipDuration: firstDur
        )
        let clampedFadeOut = Self.clampEdgeFadeSeconds(
            fadeToBlackSeconds, edgeClipDuration: lastDur
        )
        let useVideoComp = (useDual || clampedFadeIn > 0 || clampedFadeOut > 0)
            && !preset.isAudioOnly
        let useAudioMix = useDual
            || clampedFadeIn > 0
            || clampedFadeOut > 0

        // Build the composition. C18 — audio-only outputs skip the
        // video track entirely so the export session doesn't fail
        // trying to encode video into an m4a container.
        let comp = AVMutableComposition()
        var vTracks: [AVMutableCompositionTrack] = []
        var aTracks: [AVMutableCompositionTrack] = []
        if !preset.isAudioOnly {
            if let t = comp.addMutableTrack(withMediaType: .video,
                                             preferredTrackID: kCMPersistentTrackID_Invalid) {
                vTracks.append(t)
            }
            if useDual,
               let t = comp.addMutableTrack(withMediaType: .video,
                                             preferredTrackID: kCMPersistentTrackID_Invalid) {
                vTracks.append(t)
            }
        }
        if let t = comp.addMutableTrack(withMediaType: .audio,
                                         preferredTrackID: kCMPersistentTrackID_Invalid) {
            aTracks.append(t)
        }
        if useDual,
           let t = comp.addMutableTrack(withMediaType: .audio,
                                         preferredTrackID: kCMPersistentTrackID_Invalid) {
            aTracks.append(t)
        }
        if (preset.isAudioOnly && aTracks.isEmpty)
            || (!preset.isAudioOnly && vTracks.isEmpty) {
            state = .failed("Couldn't create composition tracks")
            return
        }

        // C20 — per-clip insertion offsets. With cross-fade, clip i
        // starts at `sum(durs[0..<i]) - i * cf` so consecutive
        // segments overlap by `cf`. With cf=0 this degenerates to
        // the pre-C20 cursor sum.
        var offsets: [Double] = []
        var running: Double = 0
        for (i, r) in resolved.enumerated() {
            offsets.append(i == 0 ? 0 : running - Double(i) * clampedCF)
            running += r.trimmedSeconds
        }

        // Insertion pass. With useDual=true clips alternate across
        // the two video / audio tracks (i % 2 == 0 → track A) so
        // the overlap region carries two visible layers; the video
        // composition then ramps the opacity. With useDual=false
        // there's exactly one of each track and trackIndex collapses
        // to 0.
        var collectedMarkers: [PreservedMarker] = []
        var sourceSizes: [CGSize] = []
        var firstVideoTransform: CGAffineTransform?
        let trackStride = useDual ? 2 : 1
        for (i, r) in resolved.enumerated() {
            let asset = AVURLAsset(url: r.url)
            let trackIdx = i % trackStride
            let insertAt = CMTime(seconds: offsets[i],
                                   preferredTimescale: r.timescale)
            do {
                if !preset.isAudioOnly, !vTracks.isEmpty {
                    let vSources = try await asset.loadTracks(withMediaType: .video)
                    if let v = vSources.first {
                        try vTracks[min(trackIdx, vTracks.count - 1)]
                            .insertTimeRange(r.trimRange, of: v, at: insertAt)
                        if let size = try? await v.load(.naturalSize) {
                            sourceSizes.append(size)
                        }
                        if firstVideoTransform == nil,
                           let xform = try? await v.load(.preferredTransform) {
                            firstVideoTransform = xform
                        }
                    }
                }
                let aSources = try await asset.loadTracks(withMediaType: .audio)
                if let a = aSources.first, !aTracks.isEmpty {
                    try aTracks[min(trackIdx, aTracks.count - 1)]
                        .insertTimeRange(r.trimRange, of: a, at: insertAt)
                }
                let preserved = Self.offsetMarkers(
                    r.sourceMarkers,
                    trimInSec: r.trimInSec,
                    trimOutSec: r.trimOutSec,
                    cursorSec: offsets[i]
                )
                collectedMarkers.append(contentsOf: preserved)
            } catch {
                state = .failed("Couldn't read \(r.url.lastPathComponent): \(error.localizedDescription)")
                return
            }
        }
        preservedMarkers = collectedMarkers

        // C19 — apply the target canvas size policy.
        if !vTracks.isEmpty,
           let target = Self.resolveTargetSize(mode: dimensionMode,
                                                sourceSizes: sourceSizes) {
            comp.naturalSize = target
            if let xform = firstVideoTransform {
                for vt in vTracks { vt.preferredTransform = xform }
            }
        }

        // C20 + C23 — build the optional video composition + audio
        // mix when ANY of cross-fade / fade-from-black / fade-to-
        // black is on. Pure hard-cut path leaves both nil so
        // AVAssetExportSession takes its default "play all tracks at
        // full volume / opacity" behavior.
        var videoComposition: AVMutableVideoComposition?
        var audioMix: AVMutableAudioMix?
        if useVideoComp || useAudioMix {
            let durations = resolved.map(\.trimmedSeconds)
            let timescale = resolved.first?.timescale ?? 600
            if useVideoComp, !vTracks.isEmpty {
                videoComposition = buildCrossfadeVideoComposition(
                    tracks: vTracks,
                    canvasSize: comp.naturalSize,
                    durations: durations,
                    offsets: offsets,
                    crossfade: clampedCF,
                    fadeFromBlack: clampedFadeIn,
                    fadeToBlack: clampedFadeOut,
                    timescale: timescale
                )
            }
            if useAudioMix {
                audioMix = buildCrossfadeAudioMix(
                    tracks: aTracks,
                    durations: durations,
                    offsets: offsets,
                    crossfade: clampedCF,
                    fadeFromBlack: clampedFadeIn,
                    fadeToBlack: clampedFadeOut,
                    timescale: timescale
                )
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
        session.videoComposition = videoComposition
        session.audioMix = audioMix
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

    /// C20 — pure helper that computes per-clip insertion offsets
    /// for a head-to-tail composition with optional cross-fades.
    /// Each clip's offset is `sum(durs[0..<i]) - i * crossfade`, so
    /// clip i overlaps clip i-1 by `crossfade` seconds. With
    /// crossfade=0 this degenerates to the cumulative-sum cursor of
    /// the pre-C20 hard-cut path.
    ///
    /// Combined output's total duration is
    /// `sum(durs) - (n-1) * crossfade` (or 0 for empty input).
    nonisolated static func combinedOffsets(
        trimmedDurations: [Double],
        crossfade: Double
    ) -> [Double] {
        var offsets: [Double] = []
        var running: Double = 0
        for (i, dur) in trimmedDurations.enumerated() {
            offsets.append(i == 0 ? 0 : running - Double(i) * crossfade)
            running += dur
        }
        return offsets
    }

    /// C20 + C23 — build the AVMutableVideoComposition that drives
    /// cross-fades and edge fade-from/to-black. For each clip i we
    /// emit:
    ///   - **Solo region**: when only clip i is visible. One layer
    ///     at opacity 1. The first/last clip's solo region is
    ///     trimmed by `fadeFromBlack`/`fadeToBlack` so the edge
    ///     ramp can land in its own instruction.
    ///   - **Overlap region** with clip i+1 (when i < n-1): a `cf`-
    ///     second window starting at offsets[i+1], with clip i at
    ///     opacity ramp 1→0 and clip i+1 at opacity ramp 0→1.
    ///   - **Edge fade-from-black** (C23, when fadeFromBlack > 0):
    ///     a single instruction at [0, fadeFromBlack] with the
    ///     first clip's track ramping opacity 0→1. AVFoundation's
    ///     default video-composition background is black, so a
    ///     0→1 opacity ramp reveals it as a fade-from-black.
    ///   - **Edge fade-to-black** (C23, symmetric on trailing edge):
    ///     opacity ramp 1→0 over [tail - fadeToBlack, tail].
    /// Track alternation: clip i lives on `tracks[i % tracks.count]`.
    private func buildCrossfadeVideoComposition(
        tracks: [AVMutableCompositionTrack],
        canvasSize: CGSize,
        durations: [Double],
        offsets: [Double],
        crossfade: Double,
        fadeFromBlack: Double,
        fadeToBlack: Double,
        timescale: CMTimeScale
    ) -> AVMutableVideoComposition {
        let vc = AVMutableVideoComposition()
        // Falls back to 1920×1080 when comp.naturalSize is .zero —
        // can happen on audio-only call sites that wrongly land
        // here (caller already guards but defense-in-depth is cheap).
        vc.renderSize = canvasSize == .zero ? CGSize(width: 1920, height: 1080) : canvasSize
        vc.frameDuration = CMTime(value: 1, timescale: 30)

        var instructions: [AVMutableVideoCompositionInstruction] = []
        let n = durations.count
        for i in 0..<n {
            let track = tracks[i % tracks.count]
            let segStart = offsets[i]
            let segEnd = offsets[i] + durations[i]
            // C23 — edge fades trim the first/last clip's solo
            // region further (they get their own ramp instructions
            // below). Middle clips ignore both.
            let isFirst = i == 0
            let isLast = i == n - 1
            let leadingTrim = (isFirst ? fadeFromBlack : 0)
                + (i > 0 ? crossfade : 0)
            let trailingTrim = (isLast ? fadeToBlack : 0)
                + (i < n - 1 ? crossfade : 0)
            let soloStart = segStart + leadingTrim
            let soloEnd = segEnd - trailingTrim

            if soloEnd > soloStart {
                let inst = AVMutableVideoCompositionInstruction()
                inst.timeRange = CMTimeRange(
                    start: CMTime(seconds: soloStart, preferredTimescale: timescale),
                    duration: CMTime(seconds: soloEnd - soloStart, preferredTimescale: timescale)
                )
                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                inst.layerInstructions = [layer]
                instructions.append(inst)
            }

            // C23 — leading fade-from-black on the first clip only.
            if isFirst, fadeFromBlack > 0 {
                let r = CMTimeRange(
                    start: CMTime(seconds: 0, preferredTimescale: timescale),
                    duration: CMTime(seconds: fadeFromBlack, preferredTimescale: timescale)
                )
                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                layer.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: r)
                let inst = AVMutableVideoCompositionInstruction()
                inst.timeRange = r
                inst.layerInstructions = [layer]
                instructions.append(inst)
            }
            // C23 — trailing fade-to-black on the last clip only.
            if isLast, fadeToBlack > 0 {
                let r = CMTimeRange(
                    start: CMTime(seconds: segEnd - fadeToBlack, preferredTimescale: timescale),
                    duration: CMTime(seconds: fadeToBlack, preferredTimescale: timescale)
                )
                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
                layer.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: r)
                let inst = AVMutableVideoCompositionInstruction()
                inst.timeRange = r
                inst.layerInstructions = [layer]
                instructions.append(inst)
            }

            if i < n - 1 {
                let overlapStart = offsets[i + 1]
                let overlapRange = CMTimeRange(
                    start: CMTime(seconds: overlapStart, preferredTimescale: timescale),
                    duration: CMTime(seconds: crossfade, preferredTimescale: timescale)
                )
                let outTrack = tracks[i % tracks.count]
                let inTrack = tracks[(i + 1) % tracks.count]
                let outLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: outTrack)
                outLayer.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0,
                                         timeRange: overlapRange)
                let inLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: inTrack)
                inLayer.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1,
                                        timeRange: overlapRange)
                let inst = AVMutableVideoCompositionInstruction()
                inst.timeRange = overlapRange
                // Outgoing layer must come first (top of stack) so
                // its 1→0 opacity actually reveals the incoming one
                // underneath. AVFoundation renders layer 0 last.
                inst.layerInstructions = [outLayer, inLayer]
                instructions.append(inst)
            }
        }
        // Sort by time so AVFoundation gets a contiguous timeline —
        // C23's edge-fade instruction for clip 0 may end up before
        // the solo region in our append order.
        instructions.sort { CMTimeCompare($0.timeRange.start, $1.timeRange.start) < 0 }
        vc.instructions = instructions
        return vc
    }

    /// C20 + C23 — build the AVMutableAudioMix paired with the
    /// cross-fade video composition. Each audio track carries the
    /// alternating clips; volume ramps mirror the video opacity
    /// ramps so the audio fades in and out alongside the picture.
    /// C23 — adds a leading volume ramp 0→1 on the first clip when
    /// `fadeFromBlack > 0` (silence-to-audio) and a trailing
    /// 1→0 on the last clip when `fadeToBlack > 0`.
    private func buildCrossfadeAudioMix(
        tracks: [AVMutableCompositionTrack],
        durations: [Double],
        offsets: [Double],
        crossfade: Double,
        fadeFromBlack: Double,
        fadeToBlack: Double,
        timescale: CMTimeScale
    ) -> AVMutableAudioMix {
        let mix = AVMutableAudioMix()
        var paramsByTrack: [Int: AVMutableAudioMixInputParameters] = [:]
        for (idx, track) in tracks.enumerated() {
            paramsByTrack[idx] = AVMutableAudioMixInputParameters(track: track)
        }
        let n = durations.count
        for i in 0..<n {
            let trackIdx = i % tracks.count
            guard let p = paramsByTrack[trackIdx] else { continue }
            // Leading fade-in for every clip except the first.
            if i > 0 {
                let r = CMTimeRange(
                    start: CMTime(seconds: offsets[i], preferredTimescale: timescale),
                    duration: CMTime(seconds: crossfade, preferredTimescale: timescale)
                )
                p.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: r)
            }
            // Trailing fade-out for every clip except the last.
            if i < n - 1 {
                let r = CMTimeRange(
                    start: CMTime(seconds: offsets[i] + durations[i] - crossfade,
                                   preferredTimescale: timescale),
                    duration: CMTime(seconds: crossfade, preferredTimescale: timescale)
                )
                p.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: r)
            }
            // C23 — edge fades.
            if i == 0, fadeFromBlack > 0 {
                let r = CMTimeRange(
                    start: CMTime(seconds: offsets[i], preferredTimescale: timescale),
                    duration: CMTime(seconds: fadeFromBlack, preferredTimescale: timescale)
                )
                p.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: r)
            }
            if i == n - 1, fadeToBlack > 0 {
                let r = CMTimeRange(
                    start: CMTime(seconds: offsets[i] + durations[i] - fadeToBlack,
                                   preferredTimescale: timescale),
                    duration: CMTime(seconds: fadeToBlack, preferredTimescale: timescale)
                )
                p.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: r)
            }
        }
        mix.inputParameters = Array(paramsByTrack.values)
        return mix
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
