import Foundation
import PurpleDedupCore

/// Async orchestration of the scan pipeline, lifted out of `ContentView`.
/// Two stages, each pure async work:
///
/// 1. `resolveSources` — runs PhotoKit filter resolution for any
///    `.photoslibrary` sources. Always runs, even when `filter.isActive`
///    is false: without a basename whitelist the walker can't see
///    Photos.app's hidden flag (`Photos.sqlite`-only) and would leak
///    hidden assets into the scan.
/// 2. `runEngine` — picks `CachedScanEngine` (default) or plain
///    `ScanEngine` (settings opt-out), runs it with the configured
///    options, and returns a typed `Outcome` carrying every field the
///    GUI projects onto `@State`.
///
/// Progress + status text flow back through callbacks so the GUI can
/// throttle / format them however it wants without coupling this type
/// to SwiftUI.
struct ScanCoordinator {

    let settings: AppSettings

    // MARK: - resolve

    struct Resolution {
        /// Sources after Photos library filter resolution. Folder sources
        /// pass through unchanged; `.photoslibrary` sources gain an
        /// `allowedBasenames` whitelist.
        let sources: [ScanSource]
        /// Single-line summary of the Photos filter resolution, suitable
        /// for the sidebar's `photosFilterLine`. Empty when no
        /// `.photoslibrary` source is present.
        let photosFilterLine: String
    }

    /// Resolve all `.photoslibrary` sources against PhotoKit. The
    /// `onSourceResolving` callback fires once per Photos library
    /// immediately before its resolution starts so the GUI can show a
    /// per-source "Resolving filter for X…" status.
    ///
    /// `filters` keys on `ScanSource.url.path`; missing entries fall
    /// back to a fresh `PhotoLibraryFilter()` (which produces "exclude
    /// hidden by default").
    func resolveSources(
        _ sources: [ScanSource],
        filters: [String: PhotoLibraryFilter],
        onSourceResolving: @MainActor (URL) -> Void = { _ in }
    ) async -> Resolution {
        var resolved: [ScanSource] = []
        var lastSummary: String = ""
        for src in sources {
            if src.isPhotosLibrary {
                let f = filters[src.url.path] ?? PhotoLibraryFilter()
                await MainActor.run { onSourceResolving(src.url) }
                let r = await PhotoKitDeletionService.shared
                    .matchingBasenamesDetailed(filter: f, libraryURL: src.url)
                lastSummary = f.isActive
                    ? "Photos filter: \(r.summary)"
                    : "Photos library: \(r.basenames.count) non-hidden assets (default — hidden excluded)"
                resolved.append(ScanSource(
                    url: src.url,
                    isLocked: src.isLocked,
                    allowedBasenames: r.basenames,
                    isLookupOnly: src.isLookupOnly
                ))
            } else {
                resolved.append(src)
            }
        }
        return Resolution(sources: resolved, photosFilterLine: lastSummary)
    }

    // MARK: - engine

    /// Everything `ContentView` needs to project onto `@State` after a
    /// successful scan. Wraps the engine result + (optionally) cache
    /// stats + a pre-formatted summary line.
    struct Outcome {
        let exactClusters: [ExactClusterer.Cluster]
        let similarClusters: [PerceptualClusterer.Cluster]
        let similarVideoClusters: [VideoClusterer.Cluster]
        let totalScanned: Int
        let photosLookupHashes: Set<String>
        let photosLookupCount: Int
        let clusterMembersInLookup: Set<String>
        /// Empty for the plain `ScanEngine` (no cache).
        let cacheLine: String
        let stageTiming: String
        let summaryMessage: String
    }

    /// Run the engine + project the result. Picks cached vs plain via
    /// `settings.useCachedEngine`. The plain engine is the
    /// debug-only escape hatch and does not carry the lookup index, so
    /// `Outcome.photosLookupHashes` and `clusterMembersInLookup` come
    /// back empty in that path.
    func runEngine(
        sources: [ScanSource],
        perceptual: ScanEngine.PerceptualOptions,
        video: ScanEngine.VideoOptions,
        onProgress: @Sendable @escaping (ScanProgress) -> Void
    ) async throws -> Outcome {
        if settings.useCachedEngine {
            let database = try Database.openDefault()
            // FFmpeg sidecar: only probe when the user has opted in.
            // `FFmpegProbe.find()` spawns a process to read the version
            // line, so skip it entirely when fallback is disabled.
            let ffmpegProbe: FFmpegProbe.Probe? = settings.ffmpegFallbackEnabled
                ? FFmpegProbe.find()
                : nil
            let engine = CachedScanEngine(
                database: database,
                videoFingerprinter: VideoFingerprinter(ffmpegFallback: ffmpegProbe)
            )
            let pair = try await engine.scan(
                sources: sources,
                options: ScanOptions(kinds: [.photo, .video]),
                perceptual: perceptual,
                video: video,
                progress: onProgress
            )
            let s = pair.cache
            let cacheLine = "cache: content \(s.contentHashHits)/\(s.contentHashHits + s.contentHashMisses)"
                + " · perceptual \(s.perceptualHits)/\(s.perceptualHits + s.perceptualMisses)"
                + " · video \(s.videoHits)/\(s.videoHits + s.videoMisses)"
            return Outcome(
                exactClusters: pair.result.exactClusters,
                similarClusters: pair.result.similarClusters,
                similarVideoClusters: pair.result.similarVideoClusters,
                totalScanned: pair.result.filesScanned,
                photosLookupHashes: pair.result.photosLookupHashes,
                photosLookupCount: pair.result.photosLookupCount,
                clusterMembersInLookup: pair.result.clusterMembersInLookup,
                cacheLine: cacheLine,
                stageTiming: pair.result.timing.summary(),
                summaryMessage: Self.summary(for: pair.result)
            )
        } else {
            // Plain (non-cached) engine doesn't know about lookup mode.
            // Filter lookup sources out so they don't accidentally appear
            // in clusters; the lookup index stays empty in this path.
            let scanOnly = sources.filter { !$0.isLookupOnly }
            let engine = ScanEngine()
            let result = try await engine.scan(
                sources: scanOnly,
                options: ScanOptions(kinds: [.photo, .video]),
                perceptual: perceptual,
                video: video,
                progress: onProgress
            )
            return Outcome(
                exactClusters: result.exactClusters,
                similarClusters: result.similarClusters,
                similarVideoClusters: result.similarVideoClusters,
                totalScanned: result.filesScanned,
                photosLookupHashes: result.photosLookupHashes,
                photosLookupCount: result.photosLookupCount,
                clusterMembersInLookup: [],
                cacheLine: "",
                stageTiming: "",
                summaryMessage: Self.summary(for: result)
            )
        }
    }

    /// Status-bar one-liner shared by both engine paths.
    private static func summary(for result: ScanEngine.Result) -> String {
        "Scanned \(result.filesScanned) file(s)"
        + " · \(result.exactClusters.count) exact"
        + " + \(result.similarClusters.count) similar photos"
        + " + \(result.similarVideoClusters.count) similar videos."
    }
}
