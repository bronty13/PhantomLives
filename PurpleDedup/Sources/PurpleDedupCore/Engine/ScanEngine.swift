import Foundation

/// Orchestrates a single scan: walk → exact-cluster → perceptual-cluster (photos) →
/// video-cluster. Phase 4 introduces a `CachedScanEngine` that consults the SQLite
/// fingerprint table to skip re-hashing unchanged files.
///
/// Engine instances are stateless and safe to reuse. Every call to `scan(...)` is a fresh
/// pipeline.
public actor ScanEngine {

    private let walker: FileWalker
    private let hasher: ContentHasher
    private let clusterer: ExactClusterer
    private let perceptualHasher: PerceptualHasher
    private let perceptualClusterer: PerceptualClusterer
    private let videoFingerprinter: VideoFingerprinter
    private let videoClusterer: VideoClusterer

    public init(
        walker: FileWalker = FileWalker(),
        hasher: ContentHasher = ContentHasher(),
        clusterer: ExactClusterer = ExactClusterer(),
        perceptualHasher: PerceptualHasher = PerceptualHasher(),
        perceptualClusterer: PerceptualClusterer = PerceptualClusterer(),
        videoFingerprinter: VideoFingerprinter = VideoFingerprinter(),
        videoClusterer: VideoClusterer = VideoClusterer()
    ) {
        self.walker = walker
        self.hasher = hasher
        self.clusterer = clusterer
        self.perceptualHasher = perceptualHasher
        self.perceptualClusterer = perceptualClusterer
        self.videoFingerprinter = videoFingerprinter
        self.videoClusterer = videoClusterer
    }

    /// Per-stage wall-clock durations. Filled in by `CachedScanEngine`; the plain
    /// `ScanEngine` reports zeros for the cached fields (it doesn't have a cache).
    /// Surfaced in the GUI status bar so the user can see whether time is going to
    /// I/O (walk), exact clustering, photo perceptual, or video fingerprinting.
    public struct StageTiming: Sendable {
        public var walkSeconds: Double = 0
        public var exactSeconds: Double = 0
        public var perceptualSeconds: Double = 0
        public var videoSeconds: Double = 0
        public var totalSeconds: Double = 0

        public init() {}

        public func summary() -> String {
            "walk \(String(format: "%.2f", walkSeconds))s · exact \(String(format: "%.2f", exactSeconds))s · photos \(String(format: "%.2f", perceptualSeconds))s · videos \(String(format: "%.2f", videoSeconds))s · total \(String(format: "%.2f", totalSeconds))s"
        }
    }

    public struct Result: Sendable {
        public let sources: [ScanSource]
        public let filesScanned: Int
        public let candidatesHashed: Int
        public let exactClusters: [ExactClusterer.Cluster]
        public let similarClusters: [PerceptualClusterer.Cluster]
        public let similarVideoClusters: [VideoClusterer.Cluster]
        public let similarityThreshold: Int
        public let videoSimilarityThreshold: Int
        public let timing: StageTiming

        /// Set of content hashes (lowercase hex) of every file in the
        /// `isLookupOnly` sources. The GUI uses this as a "is this folder
        /// file also in your Photos library?" oracle: if a file in a
        /// regular cluster has a content hash that's in this set, render
        /// the "Also in Photos library" badge. Empty when no lookup
        /// sources were configured.
        public let photosLookupHashes: Set<String>
        /// Counts of files that participated in the lookup index — only
        /// used for the status string ("indexed N Photos assets").
        public let photosLookupCount: Int
        /// Paths of cluster members whose cached content hash is in
        /// `photosLookupHashes`. Lets the GUI light the "In Photos" badge
        /// on perceptual / video / burst / rotated clusters too — for
        /// every file the engine had a content hash for. Files that the
        /// exact stage skipped (no same-size sibling) miss the badge;
        /// the common case where a folder copy and a Photos library copy
        /// are byte-identical is covered.
        public let clusterMembersInLookup: Set<String>

        public init(
            sources: [ScanSource],
            filesScanned: Int,
            candidatesHashed: Int,
            exactClusters: [ExactClusterer.Cluster],
            similarClusters: [PerceptualClusterer.Cluster],
            similarVideoClusters: [VideoClusterer.Cluster],
            similarityThreshold: Int,
            videoSimilarityThreshold: Int,
            timing: StageTiming = StageTiming(),
            photosLookupHashes: Set<String> = [],
            photosLookupCount: Int = 0,
            clusterMembersInLookup: Set<String> = []
        ) {
            self.sources = sources
            self.filesScanned = filesScanned
            self.candidatesHashed = candidatesHashed
            self.exactClusters = exactClusters
            self.similarClusters = similarClusters
            self.similarVideoClusters = similarVideoClusters
            self.similarityThreshold = similarityThreshold
            self.videoSimilarityThreshold = videoSimilarityThreshold
            self.timing = timing
            self.photosLookupHashes = photosLookupHashes
            self.photosLookupCount = photosLookupCount
            self.clusterMembersInLookup = clusterMembersInLookup
        }

        public func report() -> ScanReport {
            ScanReport.from(
                sources: sources,
                filesScanned: filesScanned,
                candidatesHashed: candidatesHashed,
                exactClusters: exactClusters,
                similarClusters: similarClusters,
                similarVideoClusters: similarVideoClusters,
                similarityThreshold: similarityThreshold,
                videoSimilarityThreshold: videoSimilarityThreshold
            )
        }
    }

    public struct PerceptualOptions: Sendable {
        public var enabled: Bool
        public var threshold: Int

        public init(
            enabled: Bool = true,
            threshold: Int = PerceptualClusterer.defaultThreshold
        ) {
            self.enabled = enabled
            self.threshold = threshold
        }

        public static let off = PerceptualOptions(enabled: false, threshold: 0)
    }

    public struct VideoOptions: Sendable {
        public var enabled: Bool
        public var threshold: Int

        public init(
            enabled: Bool = true,
            threshold: Int = VideoClusterer.defaultThreshold
        ) {
            self.enabled = enabled
            self.threshold = threshold
        }

        public static let off = VideoOptions(enabled: false, threshold: 0)
    }

    public func scan(
        sources: [ScanSource],
        options: ScanOptions = ScanOptions(),
        perceptual: PerceptualOptions = PerceptualOptions(),
        video: VideoOptions = VideoOptions(),
        progress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async throws -> Result {
        Log.scan.info("Scanning \(sources.count) source(s)")
        var files: [DiscoveredFile] = []
        for try await f in walker.walk(sources: sources, options: options) {
            files.append(f)
            if files.count % 256 == 0 {
                progress?(ScanProgress(
                    phase: .walking,
                    filesSeen: files.count,
                    filesHashed: 0,
                    totalCandidates: 0,
                    clustersSoFar: 0
                ))
            }
        }
        progress?(ScanProgress(
            phase: .walking,
            filesSeen: files.count,
            filesHashed: 0,
            totalCandidates: 0,
            clustersSoFar: 0
        ))

        // Stage A: exact-content clustering. Detached so the engine actor stays
        // responsive for cancellation queries during the hashing loop.
        let local = files
        let local_clusterer = clusterer
        let local_hasher = hasher
        let exactClusters = try await Task.detached(priority: .userInitiated) {
            try local_clusterer.clusterExact(
                files: local,
                hasher: local_hasher,
                progress: progress
            )
        }.value

        let candidatesHashed = countCandidates(in: files)
        let exactURLs = Set(exactClusters.flatMap { $0.files.map(\.url) })

        // Stage B: perceptual photo clustering. Photo-extension files only, with
        // exact-cluster files excluded so the same dupes don't appear twice.
        var similarClusters: [PerceptualClusterer.Cluster] = []
        if perceptual.enabled {
            let photos = files.filter { f in
                let ext = f.url.pathExtension.lowercased()
                return FileKind.photoExtensions.contains(ext)
            }
            similarClusters = try await runPerceptualStage(
                photos: photos,
                excluding: exactURLs,
                threshold: perceptual.threshold,
                progress: progress
            )
        }

        // Stage C: similar-video clustering. Video-extension files only, with exact-
        // cluster videos excluded for the same reason as Stage B.
        var similarVideoClusters: [VideoClusterer.Cluster] = []
        if video.enabled {
            let videos = files.filter { f in
                let ext = f.url.pathExtension.lowercased()
                return FileKind.videoExtensions.contains(ext)
            }
            similarVideoClusters = try await runVideoStage(
                videos: videos,
                excluding: exactURLs,
                threshold: video.threshold,
                progress: progress
            )
        }

        progress?(ScanProgress(
            phase: .done,
            filesSeen: files.count,
            filesHashed: candidatesHashed,
            totalCandidates: candidatesHashed,
            clustersSoFar: exactClusters.count + similarClusters.count + similarVideoClusters.count
        ))

        return Result(
            sources: sources,
            filesScanned: files.count,
            candidatesHashed: candidatesHashed,
            exactClusters: exactClusters,
            similarClusters: similarClusters,
            similarVideoClusters: similarVideoClusters,
            similarityThreshold: perceptual.enabled ? perceptual.threshold : 0,
            videoSimilarityThreshold: video.enabled ? video.threshold : 0
        )
    }

    /// Hash all photos perceptually, then cluster on the BK-tree. Hashing is the
    /// expensive step (~5-10 ms per photo on M-series); we parallelise it via TaskGroup
    /// so a folder of 1000 photos completes in seconds, not minutes.
    private func runPerceptualStage(
        photos: [DiscoveredFile],
        excluding excludeURLs: Set<URL>,
        threshold: Int,
        progress: (@Sendable (ScanProgress) -> Void)?
    ) async throws -> [PerceptualClusterer.Cluster] {
        guard !photos.isEmpty else { return [] }

        let hasher = perceptualHasher
        var entries: [(DiscoveredFile, PerceptualHash)] = []
        entries.reserveCapacity(photos.count)

        try await withThrowingTaskGroup(of: (DiscoveredFile, PerceptualHash)?.self) { group in
            // See CachedScanEngine.runPerceptualStage for why we cap at 6 — HEIC
            // embedded-thumbnail decode goes through the hardware HEVC decoder which
            // serializes high concurrency.
            let limit = max(2, min(6, ProcessInfo.processInfo.activeProcessorCount))
            var iterator = photos.makeIterator()
            var inFlight = 0

            func submit() {
                guard let next = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    do {
                        let h = try hasher.hash(imageAt: next.url)
                        return (next, h)
                    } catch {
                        Log.hash.notice("Perceptual hash failed for \(next.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        return nil
                    }
                }
            }

            for _ in 0..<limit { submit() }

            var done = 0
            while inFlight > 0 {
                if let result = try await group.next() {
                    inFlight -= 1
                    done += 1
                    if let r = result { entries.append(r) }
                    if done % 32 == 0 {
                        progress?(ScanProgress(
                            phase: .hashing,
                            filesSeen: photos.count,
                            filesHashed: done,
                            totalCandidates: photos.count,
                            clustersSoFar: 0
                        ))
                    }
                    submit()
                } else {
                    break
                }
            }
        }

        Log.hash.info("Perceptual: hashed \(entries.count)/\(photos.count) photo(s)")

        let clusterer = perceptualClusterer
        let entries_local = entries
        let exclude_local = excludeURLs
        let threshold_local = threshold
        return await Task.detached(priority: .userInitiated) {
            clusterer.clusterSimilar(
                entries: entries_local,
                threshold: threshold_local,
                excluding: exclude_local
            )
        }.value
    }

    /// Fingerprint each video at 1 fps via AVFoundation, then cluster aligned sequences.
    /// Concurrency: 4 in-flight fingerprinters (each spins up its own AVAssetImageGenerator,
    /// which is internally multi-threaded — oversubscribing here just adds contention).
    private func runVideoStage(
        videos: [DiscoveredFile],
        excluding excludeURLs: Set<URL>,
        threshold: Int,
        progress: (@Sendable (ScanProgress) -> Void)?
    ) async throws -> [VideoClusterer.Cluster] {
        guard !videos.isEmpty else { return [] }

        let fingerprinter = videoFingerprinter
        var entries: [(DiscoveredFile, VideoFingerprint)] = []
        entries.reserveCapacity(videos.count)

        try await withThrowingTaskGroup(of: (DiscoveredFile, VideoFingerprint)?.self) { group in
            let limit = 4   // AVFoundation parallelism — see comment above
            var iterator = videos.makeIterator()
            var inFlight = 0

            func submit() {
                guard let next = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    do {
                        let fp = try await fingerprinter.fingerprint(videoAt: next.url)
                        return (next, fp)
                    } catch {
                        Log.hash.notice("Video fingerprint failed for \(next.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        return nil
                    }
                }
            }

            for _ in 0..<limit { submit() }

            var done = 0
            while inFlight > 0 {
                if let result = try await group.next() {
                    inFlight -= 1
                    done += 1
                    if let r = result { entries.append(r) }
                    if done % 8 == 0 {
                        progress?(ScanProgress(
                            phase: .hashing,
                            filesSeen: videos.count,
                            filesHashed: done,
                            totalCandidates: videos.count,
                            clustersSoFar: 0
                        ))
                    }
                    submit()
                } else {
                    break
                }
            }
        }

        Log.hash.info("Video: fingerprinted \(entries.count)/\(videos.count) video(s)")

        let clusterer = videoClusterer
        let entries_local = entries
        let exclude_local = excludeURLs
        let threshold_local = threshold
        return await Task.detached(priority: .userInitiated) {
            clusterer.clusterSimilar(
                entries: entries_local,
                threshold: threshold_local,
                excluding: exclude_local
            )
        }.value
    }

    /// Mirrors Stage 1 logic so the result struct can report how many files we actually
    /// hashed (= had to fully read off disk). Useful for the "we got 80% out of size
    /// bucketing alone" insight in CLI output.
    private nonisolated func countCandidates(in files: [DiscoveredFile]) -> Int {
        var bySize: [Int64: Int] = [:]
        for f in files { bySize[f.sizeBytes, default: 0] += 1 }
        return bySize.values.filter { $0 >= 2 }.reduce(0, +)
    }
}
