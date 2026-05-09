import Foundation

/// Scan engine with on-disk cache. Reuses the per-stage components from `ScanEngine`
/// but consults the SQLite `files` + `fingerprints` tables before deciding whether
/// to actually re-hash a file. The cache key is `(path, sizeBytes, mtimeUnix)` — if
/// any field disagrees with the persisted row, the file is considered stale and gets
/// re-hashed.
///
/// Targets FR-6.3: ≥10× speedup on second runs against unchanged libraries. The win
/// comes from skipping SHA256 (the dominant cost on large photo libraries) and the
/// vDSP DCT (the dominant cost on video-heavy libraries).
///
/// Threshold-without-rescan: calling `scan(...)` again with a different perceptual
/// threshold (and the same source paths) keeps the I/O and hashing skip-rate at
/// 100%; only the clusterers re-run. No separate `recluster` API needed today —
/// the cached `scan` is fast enough that a GUI threshold-stepper change feels live.
public actor CachedScanEngine {

    private let database: Database
    private let walker: FileWalker
    private let exactClusterer: ExactClusterer
    private let perceptualClusterer: PerceptualClusterer
    private let videoClusterer: VideoClusterer
    private let contentHasher: ContentHasher
    private let perceptualHasher: PerceptualHasher
    private let videoFingerprinter: VideoFingerprinter

    public init(
        database: Database,
        walker: FileWalker = FileWalker(),
        exactClusterer: ExactClusterer = ExactClusterer(),
        perceptualClusterer: PerceptualClusterer = PerceptualClusterer(),
        videoClusterer: VideoClusterer = VideoClusterer(),
        contentHasher: ContentHasher = ContentHasher(),
        perceptualHasher: PerceptualHasher = PerceptualHasher(),
        videoFingerprinter: VideoFingerprinter = VideoFingerprinter()
    ) {
        self.database = database
        self.walker = walker
        self.exactClusterer = exactClusterer
        self.perceptualClusterer = perceptualClusterer
        self.videoClusterer = videoClusterer
        self.contentHasher = contentHasher
        self.perceptualHasher = perceptualHasher
        self.videoFingerprinter = videoFingerprinter
    }

    /// Convenient counters, surfaced so the GUI can show "skipped 1,247 files via cache."
    public struct CacheStats: Sendable {
        public var contentHashHits: Int = 0
        public var contentHashMisses: Int = 0
        public var perceptualHits: Int = 0
        public var perceptualMisses: Int = 0
        public var videoHits: Int = 0
        public var videoMisses: Int = 0
    }

    public func scan(
        sources: [ScanSource],
        options: ScanOptions = ScanOptions(),
        perceptual: ScanEngine.PerceptualOptions = ScanEngine.PerceptualOptions(),
        video: ScanEngine.VideoOptions = ScanEngine.VideoOptions(),
        progress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async throws -> (result: ScanEngine.Result, cache: CacheStats) {
        Log.scan.info("CachedScanEngine: scanning \(sources.count) source(s)")
        let scanStart = Date()
        var stats = CacheStats()
        var timing = ScanEngine.StageTiming()

        // Split sources by mode. Lookup-only sources contribute to the
        // "is this also in your Photos library?" reference index but skip
        // every clustering / perceptual / video stage. Saves wall time and
        // means lookup files never appear in the result clusters.
        let lookupSources = sources.filter { $0.isLookupOnly }
        let scanSources = sources.filter { !$0.isLookupOnly }

        // Bulk-load every cached row in one read. Per-stage code below does an
        // O(1) dict lookup instead of `SELECT … WHERE path = ?` per file.
        let cachedRows = (try? database.loadAllCachedRows()) ?? [:]
        Log.scan.info("Loaded \(cachedRows.count) cached row(s) in one query")

        // Build the Photos lookup index BEFORE the main scan, so the result
        // can carry it through to the GUI without a second pass. Cache
        // hit-rate dominates here on second runs of an unchanged library.
        let lookupHashes: Set<String>
        let lookupCount: Int
        if !lookupSources.isEmpty {
            let lookupStart = Date()
            let (h, c) = try await buildLookupIndex(
                sources: lookupSources,
                options: options,
                cachedRows: cachedRows,
                stats: &stats
            )
            lookupHashes = h
            lookupCount = c
            FileHandle.standardError.write(Data(
                "[STAGE lookup]    \(String(format: "%.2f", Date().timeIntervalSince(lookupStart)))s (\(c) Photos assets indexed)\n".utf8
            ))
        } else {
            lookupHashes = []
            lookupCount = 0
        }

        // Walk the filesystem (scan-mode sources only).
        let walkStart = Date()
        var files: [DiscoveredFile] = []
        for try await f in walker.walk(sources: scanSources, options: options) {
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

        // Stage A: exact-content clustering using cached SHA256s where the cache
        // is fresh. We compute the size buckets first so we only consult the cache
        // for files that have ≥1 same-size sibling (Stage 1 short-circuit).
        timing.walkSeconds = walkStart.distance(to: Date()) - 0  // rough; full walk above
        let exactStart = Date()
        let exactClusters = try await runExactStage(files: files, cachedRows: cachedRows, stats: &stats, progress: progress)
        timing.exactSeconds = Date().timeIntervalSince(exactStart)
        FileHandle.standardError.write(Data("[STAGE exact] \(String(format: "%.2f", timing.exactSeconds))s\n".utf8))

        let candidatesHashed = countCandidates(in: files)
        let exactURLs = Set(exactClusters.flatMap { $0.files.map(\.url) })

        // Stages B & C run in PARALLEL via async-let. They use independent decode
        // paths (ImageIO/VideoToolbox HEVC for photos, AVFoundation for videos) and
        // hardware queues, so contention is minimal. Wall time = max(B, C) instead
        // of B + C — on a Live-Photo-heavy iPhone library that cuts ~40% off cold
        // scan time. The trade-off: peak memory while both stages run.
        let photos: [DiscoveredFile]
        if perceptual.enabled {
            photos = files.filter { f in
                let ext = f.url.pathExtension.lowercased()
                return FileKind.photoExtensions.contains(ext)
            }
        } else {
            photos = []
        }

        let videos: [DiscoveredFile]
        if video.enabled {
            let allVideos = files.filter { f in
                let ext = f.url.pathExtension.lowercased()
                return FileKind.videoExtensions.contains(ext)
            }
            let livePhotoMOVs = Self.livePhotoCompanions(in: files)
            videos = allVideos.filter { !livePhotoMOVs.contains($0.url) }
            if videos.count < allVideos.count {
                Log.scan.info("Skipping \(allVideos.count - videos.count) Live Photo .MOV companion(s)")
            }
        } else {
            videos = []
        }

        // Async-let lets us start both stages concurrently and await them at the
        // single `try await` line below. Stats updates need explicit isolation;
        // each stage owns its own local `CacheStats` copy and we merge after.
        var perceptualStats = CacheStats()
        var videoStats = CacheStats()
        let pthreshold = perceptual.threshold
        let vthreshold = video.threshold
        async let perceptualResult: [PerceptualClusterer.Cluster] = {
            guard perceptual.enabled, !photos.isEmpty else { return [] }
            return try await runPerceptualStage(
                photos: photos,
                cachedRows: cachedRows,
                excluding: exactURLs,
                threshold: pthreshold,
                stats: &perceptualStats,
                progress: progress
            )
        }()
        async let videoResult: [VideoClusterer.Cluster] = {
            guard video.enabled, !videos.isEmpty else { return [] }
            return try await runVideoStage(
                videos: videos,
                cachedRows: cachedRows,
                excluding: exactURLs,
                threshold: vthreshold,
                stats: &videoStats,
                progress: progress
            )
        }()
        let parallelStart = Date()
        let similarClusters = try await perceptualResult
        timing.perceptualSeconds = Date().timeIntervalSince(parallelStart)
        let similarVideoClusters = try await videoResult
        timing.videoSeconds = Date().timeIntervalSince(parallelStart)
        FileHandle.standardError.write(Data(
            "[STAGE perceptual] \(String(format: "%.2f", timing.perceptualSeconds))s (\(photos.count) photos)\n".utf8
        ))
        FileHandle.standardError.write(Data(
            "[STAGE video]      \(String(format: "%.2f", timing.videoSeconds))s (\(videos.count) videos)\n".utf8
        ))
        // Merge per-stage stats back into the shared counter.
        stats.perceptualHits += perceptualStats.perceptualHits
        stats.perceptualMisses += perceptualStats.perceptualMisses
        stats.videoHits += videoStats.videoHits
        stats.videoMisses += videoStats.videoMisses

        progress?(ScanProgress(
            phase: .done,
            filesSeen: files.count,
            filesHashed: candidatesHashed,
            totalCandidates: candidatesHashed,
            clustersSoFar: exactClusters.count + similarClusters.count + similarVideoClusters.count
        ))

        Log.scan.info("CachedScanEngine: cache content=\(stats.contentHashHits)/\(stats.contentHashHits + stats.contentHashMisses) perceptual=\(stats.perceptualHits)/\(stats.perceptualHits + stats.perceptualMisses) video=\(stats.videoHits)/\(stats.videoHits + stats.videoMisses)")

        timing.totalSeconds = Date().timeIntervalSince(scanStart)
        let result = ScanEngine.Result(
            sources: sources,
            filesScanned: files.count,
            candidatesHashed: candidatesHashed,
            exactClusters: exactClusters,
            similarClusters: similarClusters,
            similarVideoClusters: similarVideoClusters,
            similarityThreshold: perceptual.enabled ? perceptual.threshold : 0,
            videoSimilarityThreshold: video.enabled ? video.threshold : 0,
            timing: timing,
            photosLookupHashes: lookupHashes,
            photosLookupCount: lookupCount
        )
        return (result, stats)
    }

    /// Build the "is this in your Photos library?" hash set. Walks the
    /// lookup-only sources, computes a SHA-1 (or whatever the configured
    /// content hasher is) for each file, and returns the union as a set
    /// of lowercase hex strings. Cache-aware: previously hashed files
    /// short-circuit, so a second scan over the same library is fast.
    ///
    /// Unlike `runExactStage`, this hashes EVERY file — there's no size
    /// bucket short-circuit, because singleton files in the library still
    /// matter as lookup targets ("yes, you have this exact byte sequence
    /// in your library, even if it's the only copy").
    private func buildLookupIndex(
        sources: [ScanSource],
        options: ScanOptions,
        cachedRows: [String: Database.CachedRow],
        stats: inout CacheStats
    ) async throws -> (hashes: Set<String>, count: Int) {
        var files: [DiscoveredFile] = []
        for try await f in walker.walk(sources: sources, options: options) {
            files.append(f)
        }
        guard !files.isEmpty else { return ([], 0) }

        var hashes: Set<String> = []
        var staleFiles: [DiscoveredFile] = []
        for f in files {
            if let row = cachedRows[f.url.path],
               row.file.sizeBytes == f.sizeBytes,
               row.file.mtimeUnix == Int64(f.modificationTime.timeIntervalSince1970),
               let blob = row.file.contentHash {
                hashes.insert(blob.hexEncodedString())
                stats.contentHashHits += 1
            } else {
                staleFiles.append(f)
            }
        }
        stats.contentHashMisses += staleFiles.count

        // Parallel hash for stale files — same shape as runExactStage but
        // we only need the hex hashes, no clustering.
        let hasher = contentHasher
        let local_classify = classify(extension:)
        var freshHashes: [(DiscoveredFile, Data)] = []
        try await withThrowingTaskGroup(of: (DiscoveredFile, Data)?.self) { group in
            let limit = max(2, ProcessInfo.processInfo.activeProcessorCount)
            var iterator = staleFiles.makeIterator()
            var inFlight = 0

            func submit() {
                guard let next = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    do {
                        let blob = try hasher.hash(fileAt: next.url)
                        return (next, blob)
                    } catch {
                        Log.hash.notice("Lookup hash failed for \(next.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        return nil
                    }
                }
            }
            for _ in 0..<limit { submit() }
            while inFlight > 0 {
                if let r = try await group.next() {
                    inFlight -= 1
                    if let entry = r {
                        freshHashes.append(entry)
                        hashes.insert(entry.1.hexEncodedString())
                    }
                    submit()
                } else { break }
            }
        }

        // Persist the freshly-hashed lookup files so the next scan reads
        // them straight from cache. Same batch shape as the main exact
        // stage uses — keeps the cache schema consistent.
        if !freshHashes.isEmpty {
            let rows = freshHashes.map { (f, blob) in
                Database.ScannedFile(
                    path: f.url.path,
                    sizeBytes: f.sizeBytes,
                    mtimeUnix: Int64(f.modificationTime.timeIntervalSince1970),
                    fileType: local_classify(f.url.pathExtension),
                    format: f.url.pathExtension.lowercased(),
                    contentHash: blob
                )
            }
            try database.upsertScannedBatch(rows)
        }
        return (hashes, files.count)
    }

    // MARK: - Stage A (exact)

    private func runExactStage(
        files: [DiscoveredFile],
        cachedRows: [String: Database.CachedRow],
        stats: inout CacheStats,
        progress: (@Sendable (ScanProgress) -> Void)?
    ) async throws -> [ExactClusterer.Cluster] {

        // Stage 1: size bucket.
        var bySize: [Int64: [DiscoveredFile]] = [:]
        for f in files { bySize[f.sizeBytes, default: []].append(f) }
        let candidates = bySize.values.filter { $0.count >= 2 }.flatMap { $0 }

        // Cache lookup pass — pure in-memory dict access; no SQLite round trips.
        var cachedHashes: [URL: String] = [:]
        var staleFiles: [DiscoveredFile] = []
        for f in candidates {
            if let row = cachedRows[f.url.path],
               row.file.sizeBytes == f.sizeBytes,
               row.file.mtimeUnix == Int64(f.modificationTime.timeIntervalSince1970),
               let blob = row.file.contentHash {
                cachedHashes[f.url] = blob.hexEncodedString()
                stats.contentHashHits += 1
            } else {
                staleFiles.append(f)
            }
        }
        stats.contentHashMisses += staleFiles.count

        // Parallel SHA256 pass for stale files. Previously this stage was serial — on
        // an M-series machine that left 15 cores idle while one churned through the
        // disk reads. Concurrency capped at activeProcessorCount (M4 Max = 16).
        let hasher = contentHasher
        let local_classify = classify(extension:)
        var freshResults: [(DiscoveredFile, Data)] = []
        try await withThrowingTaskGroup(of: (DiscoveredFile, Data)?.self) { group in
            let limit = max(2, ProcessInfo.processInfo.activeProcessorCount)
            var iterator = staleFiles.makeIterator()
            var inFlight = 0

            func submit() {
                guard let next = iterator.next() else { return }
                inFlight += 1
                group.addTask {
                    do {
                        let blob = try hasher.hash(fileAt: next.url)
                        return (next, blob)
                    } catch {
                        Log.hash.notice("Hash failed for \(next.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        return nil
                    }
                }
            }

            for _ in 0..<limit { submit() }
            var done = 0
            while inFlight > 0 {
                if let r = try await group.next() {
                    inFlight -= 1; done += 1
                    if let entry = r { freshResults.append(entry) }
                    if done % 64 == 0 {
                        progress?(ScanProgress(
                            phase: .hashing,
                            filesSeen: files.count,
                            filesHashed: cachedHashes.count + done,
                            totalCandidates: candidates.count,
                            clustersSoFar: 0
                        ))
                    }
                    submit()
                } else { break }
            }
        }

        // Persist all fresh hashes in ONE transaction. Per-file upsertScanned calls
        // were the second-largest cost on large libraries — each was its own SQLite
        // transaction with an fsync. Batched to one transaction per stage.
        if !freshResults.isEmpty {
            let now = Date().timeIntervalSince1970
            _ = now  // ensure we don't recompute mtime per row
            let rows = freshResults.map { (f, blob) in
                Database.ScannedFile(
                    path: f.url.path,
                    sizeBytes: f.sizeBytes,
                    mtimeUnix: Int64(f.modificationTime.timeIntervalSince1970),
                    fileType: local_classify(f.url.pathExtension),
                    format: f.url.pathExtension.lowercased(),
                    contentHash: blob
                )
            }
            try database.upsertScannedBatch(rows)
        }

        // Cluster.
        var byHash: [String: [DiscoveredFile]] = [:]
        for f in candidates {
            if let hex = cachedHashes[f.url] {
                byHash[hex, default: []].append(f)
            }
        }
        for (f, blob) in freshResults {
            byHash[blob.hexEncodedString(), default: []].append(f)
        }

        var clusters: [ExactClusterer.Cluster] = []
        for (hex, members) in byHash where members.count >= 2 {
            clusters.append(ExactClusterer.Cluster(
                contentHashHex: hex,
                sizeBytes: members.first!.sizeBytes,
                files: members.sorted { $0.url.path < $1.url.path }
            ))
        }
        let sorted = clusters.sorted {
            if $0.totalReclaimableBytes != $1.totalReclaimableBytes {
                return $0.totalReclaimableBytes > $1.totalReclaimableBytes
            }
            return $0.contentHashHex < $1.contentHashHex
        }
        return sorted
    }

    // MARK: - Stage B (perceptual)

    private func runPerceptualStage(
        photos: [DiscoveredFile],
        cachedRows: [String: Database.CachedRow],
        excluding excludeURLs: Set<URL>,
        threshold: Int,
        stats: inout CacheStats,
        progress: (@Sendable (ScanProgress) -> Void)?
    ) async throws -> [PerceptualClusterer.Cluster] {
        guard !photos.isEmpty else { return [] }

        // Pure in-memory cache lookup — no SQLite round trips.
        var cachedEntries: [(DiscoveredFile, PerceptualHash)] = []
        var staleFiles: [DiscoveredFile] = []

        for f in photos {
            if let row = cachedRows[f.url.path],
               row.file.sizeBytes == f.sizeBytes,
               row.file.mtimeUnix == Int64(f.modificationTime.timeIntervalSince1970),
               let fp = row.fingerprint,
               let phashBlob = fp.phash,
               let dhashBlob = fp.dhash {
                let phash = UInt64(littleEndianHashData: phashBlob)
                let dhash = UInt64(littleEndianHashData: dhashBlob)
                let h = PerceptualHash(
                    phash: phash, dhash: dhash,
                    width: Int(fp.width ?? 0), height: Int(fp.height ?? 0)
                )
                cachedEntries.append((f, h))
                stats.perceptualHits += 1
            } else {
                staleFiles.append(f)
            }
        }
        stats.perceptualMisses += staleFiles.count

        // Hash stale files concurrently. DB writes are batched at the end of the
        // stage rather than per-task — each upsertFingerprint was its own SQLite
        // transaction (with fsync), serializing through GRDB's writer queue. On a
        // 10K-photo library this dominated the wall clock more than the DCT itself.
        let hasher = perceptualHasher
        let local_classify = classify(extension:)
        var freshEntries: [(DiscoveredFile, PerceptualHash)] = []
        try await withThrowingTaskGroup(of: (DiscoveredFile, PerceptualHash)?.self) { group in
            // Concurrency cap: HEIC's embedded thumbnail is itself HEVC-compressed,
            // and macOS's hardware HEVC decoder serializes concurrent VideoToolbox
            // sessions. Sampling a stuck scan showed all 16 worker threads parked in
            // VTTileDecompressionSessionDecodeTile. Capped at 6 — empirically this
            // saturates the decoder on M-series without contention. For pure-JPEG
            // libraries the cap is harmless: JPEG decode is software, fast, and
            // unaffected by the HEVC decoder's scheduling.
            let limit = max(2, min(6, ProcessInfo.processInfo.activeProcessorCount))
            var iterator = staleFiles.makeIterator()
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
                if let r = try await group.next() {
                    inFlight -= 1; done += 1
                    if let entry = r { freshEntries.append(entry) }
                    if done % 32 == 0 {
                        progress?(ScanProgress(
                            phase: .hashing,
                            filesSeen: photos.count,
                            filesHashed: cachedEntries.count + done,
                            totalCandidates: photos.count,
                            clustersSoFar: 0
                        ))
                    }
                    submit()
                } else { break }
            }
        }

        // Batch persist.
        if !freshEntries.isEmpty {
            let rows = freshEntries.map { (f, h) in
                Database.FingerprintWrite(
                    path: f.url.path,
                    sizeBytes: f.sizeBytes,
                    mtimeUnix: Int64(f.modificationTime.timeIntervalSince1970),
                    fileType: local_classify(f.url.pathExtension),
                    format: f.url.pathExtension.lowercased(),
                    phash: h.phash,
                    dhash: h.dhash,
                    width: h.width,
                    height: h.height,
                    videoFingerprint: nil
                )
            }
            try database.upsertFingerprintsBatch(rows)
        }

        let allEntries = cachedEntries + freshEntries
        let clusterer = perceptualClusterer
        let entries_local = allEntries
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

    // MARK: - Stage C (video)

    private func runVideoStage(
        videos: [DiscoveredFile],
        cachedRows: [String: Database.CachedRow],
        excluding excludeURLs: Set<URL>,
        threshold: Int,
        stats: inout CacheStats,
        progress: (@Sendable (ScanProgress) -> Void)?
    ) async throws -> [VideoClusterer.Cluster] {
        guard !videos.isEmpty else { return [] }

        var cachedEntries: [(DiscoveredFile, VideoFingerprint)] = []
        var staleFiles: [DiscoveredFile] = []

        for f in videos {
            if let row = cachedRows[f.url.path],
               row.file.sizeBytes == f.sizeBytes,
               row.file.mtimeUnix == Int64(f.modificationTime.timeIntervalSince1970),
               let fp = row.fingerprint,
               let blob = fp.videoFingerprint,
               let decoded = decodeVideoFingerprint(blob) {
                cachedEntries.append((f, decoded))
                stats.videoHits += 1
            } else {
                staleFiles.append(f)
            }
        }
        stats.videoMisses += staleFiles.count

        let fingerprinter = videoFingerprinter
        let local_classify = classify(extension:)
        var freshEntries: [(DiscoveredFile, VideoFingerprint)] = []
        try await withThrowingTaskGroup(of: (DiscoveredFile, VideoFingerprint)?.self) { group in
            // AVFoundation is internally multi-threaded; we still bump from 4→8 here
            // because on M-series there's slack and a higher limit measurably helps
            // on libraries with many short videos.
            let limit = max(4, min(8, ProcessInfo.processInfo.activeProcessorCount / 2))
            var iterator = staleFiles.makeIterator()
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
                if let r = try await group.next() {
                    inFlight -= 1; done += 1
                    if let entry = r { freshEntries.append(entry) }
                    if done % 8 == 0 {
                        progress?(ScanProgress(
                            phase: .hashing,
                            filesSeen: videos.count,
                            filesHashed: cachedEntries.count + done,
                            totalCandidates: videos.count,
                            clustersSoFar: 0
                        ))
                    }
                    submit()
                } else { break }
            }
        }

        // Batch persist video fingerprints.
        if !freshEntries.isEmpty {
            let rows = freshEntries.map { (f, fp) in
                Database.FingerprintWrite(
                    path: f.url.path,
                    sizeBytes: f.sizeBytes,
                    mtimeUnix: Int64(f.modificationTime.timeIntervalSince1970),
                    fileType: local_classify(f.url.pathExtension),
                    format: f.url.pathExtension.lowercased(),
                    phash: nil,
                    dhash: nil,
                    width: fp.width,
                    height: fp.height,
                    videoFingerprint: fp.encoded()
                )
            }
            try database.upsertFingerprintsBatch(rows)
        }

        let allEntries = cachedEntries + freshEntries
        let clusterer = videoClusterer
        let entries_local = allEntries
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

    // MARK: - helpers

    /// Inverse of `VideoFingerprint.encoded()`. Returns nil for malformed blobs (a
    /// schema change would surface as nil here, prompting a re-fingerprint).
    private nonisolated func decodeVideoFingerprint(_ data: Data) -> VideoFingerprint? {
        guard data.count >= 18 else { return nil }
        let count = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt16.self).littleEndian }
        let width = data.withUnsafeBytes { $0.load(fromByteOffset: 2, as: UInt16.self).littleEndian }
        let height = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt16.self).littleEndian }
        let durationBits = data.withUnsafeBytes { $0.load(fromByteOffset: 6, as: UInt64.self).littleEndian }
        let rateBits = data.withUnsafeBytes { $0.load(fromByteOffset: 14, as: UInt32.self).littleEndian }
        let duration = Double(bitPattern: durationBits)
        let rate = Float(bitPattern: rateBits)

        let expected = 18 + Int(count) * 8
        guard data.count == expected else { return nil }

        var hashes: [UInt64] = []
        hashes.reserveCapacity(Int(count))
        for i in 0..<Int(count) {
            let off = 18 + i * 8
            let v = data.withUnsafeBytes { $0.load(fromByteOffset: off, as: UInt64.self).littleEndian }
            hashes.append(v)
        }
        return VideoFingerprint(
            frameHashes: hashes,
            durationSeconds: duration,
            width: Int(width),
            height: Int(height),
            sampleRate: Double(rate)
        )
    }

    /// Identify .MOV files that are Live Photo companions: same parent directory + same
    /// basename + a sibling .HEIC (or .JPG, for older iPhones). These are short clips
    /// paired with a still photo; fingerprinting them is wasted work and the still half
    /// already carries the perceptually-distinct content.
    private static func livePhotoCompanions(in files: [DiscoveredFile]) -> Set<URL> {
        var byKey: [String: [DiscoveredFile]] = [:]
        for f in files {
            let dir = f.url.deletingLastPathComponent().path
            let stem = (f.url.lastPathComponent as NSString).deletingPathExtension
            let key = "\(dir)/\(stem)"
            byKey[key, default: []].append(f)
        }
        var movs: Set<URL> = []
        for (_, group) in byKey where group.count >= 2 {
            let exts = group.map { $0.url.pathExtension.lowercased() }
            // Live Photo signature: at least one HEIC/JPG and at least one MOV with the
            // same stem. Filter the .MOV out of the video stage; keep the HEIC/JPG for
            // the photo stage.
            let hasStill = exts.contains(where: { ["heic", "heif", "jpg", "jpeg"].contains($0) })
            let movMembers = group.filter { $0.url.pathExtension.lowercased() == "mov" }
            if hasStill, !movMembers.isEmpty {
                for m in movMembers { movs.insert(m.url) }
            }
        }
        return movs
    }

    private nonisolated func classify(extension ext: String) -> String {
        let lower = ext.lowercased()
        if FileKind.photoExtensions.contains(lower) { return "photo" }
        if FileKind.videoExtensions.contains(lower) { return "video" }
        return "other"
    }

    private nonisolated func countCandidates(in files: [DiscoveredFile]) -> Int {
        var bySize: [Int64: Int] = [:]
        for f in files { bySize[f.sizeBytes, default: 0] += 1 }
        return bySize.values.filter { $0 >= 2 }.reduce(0, +)
    }
}
