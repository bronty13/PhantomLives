import Foundation

/// Phase 1 clusterer: groups files by exact content. Implements the staged hashing pipeline
/// from the requirements:
///
///   Stage 1: bucket by `sizeBytes`. Files with a unique size can never be exact dupes
///            of anything, so they exit the pipeline immediately for free.
///   Stage 3: full SHA256 hash for size-bucket survivors. Files sharing a hash form a
///            cluster.
///
/// Stage 2 (partial-hash quick filter) is a worthwhile optimization for very large
/// libraries but has been deferred — at typical photo/video sizes the win is small and the
/// extra code path is one more thing to test. Worth revisiting in Phase 7 if profiling
/// shows hashing is the bottleneck.
public struct ExactClusterer: Sendable {

    public struct Cluster: Sendable, Hashable {
        public let contentHashHex: String
        public let sizeBytes: Int64
        public let files: [DiscoveredFile]

        public init(contentHashHex: String, sizeBytes: Int64, files: [DiscoveredFile]) {
            self.contentHashHex = contentHashHex
            self.sizeBytes = sizeBytes
            self.files = files
        }

        public var totalReclaimableBytes: Int64 {
            // Keep one copy, the rest is reclaimable. If every file is locked there's
            // nothing to actually delete, but the cluster is still surfaced for review.
            sizeBytes * Int64(max(0, files.count - 1))
        }
    }

    public init() {}

    /// Synchronous variant. Useful for tests and small CLI scans where we already have a
    /// materialized list of files in memory.
    public func clusterExact(
        files: [DiscoveredFile],
        hasher: ContentHasher = ContentHasher(),
        progress: ((ScanProgress) -> Void)? = nil
    ) throws -> [Cluster] {

        // Stage 1: size buckets.
        var bySize: [Int64: [DiscoveredFile]] = [:]
        for f in files {
            // Zero-byte files all have the same SHA256 ("e3b0c4..."); treat as exact dupes
            // intentionally — they probably are. Skipping them would hide real cleanup
            // opportunities in folders full of empty placeholders.
            bySize[f.sizeBytes, default: []].append(f)
        }
        let candidates = bySize.values.filter { $0.count >= 2 }.flatMap { $0 }
        progress?(ScanProgress(
            phase: .hashing,
            filesSeen: files.count,
            filesHashed: 0,
            totalCandidates: candidates.count,
            clustersSoFar: 0
        ))

        Log.cluster.info("Stage 1: \(files.count) files → \(candidates.count) size-bucket candidates")

        // Stage 3: SHA256 hash candidates and group by digest.
        var byHash: [String: [DiscoveredFile]] = [:]
        // Deterministic per-bucket hash size for the cluster `sizeBytes`. We use the file's
        // own size (all files in a hash group share size by construction).
        var sizeForHash: [String: Int64] = [:]
        var hashed = 0
        for f in candidates {
            try Task.checkCancellation()
            let hex: String
            do {
                hex = try hasher.hexHash(fileAt: f.url)
            } catch {
                Log.hash.notice("Hash failed for \(f.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continue
            }
            byHash[hex, default: []].append(f)
            sizeForHash[hex] = f.sizeBytes
            hashed += 1
            if hashed % 64 == 0 {
                progress?(ScanProgress(
                    phase: .hashing,
                    filesSeen: files.count,
                    filesHashed: hashed,
                    totalCandidates: candidates.count,
                    clustersSoFar: byHash.values.filter { $0.count >= 2 }.count
                ))
            }
        }

        let clusters: [Cluster] = byHash.compactMap { hex, members in
            guard members.count >= 2 else { return nil }
            return Cluster(
                contentHashHex: hex,
                sizeBytes: sizeForHash[hex] ?? 0,
                files: members.sorted { $0.url.path < $1.url.path }
            )
        }
        // Stable order: largest reclaimable first, ties by hash for reproducibility.
        let sorted = clusters.sorted {
            if $0.totalReclaimableBytes != $1.totalReclaimableBytes {
                return $0.totalReclaimableBytes > $1.totalReclaimableBytes
            }
            return $0.contentHashHex < $1.contentHashHex
        }

        progress?(ScanProgress(
            phase: .done,
            filesSeen: files.count,
            filesHashed: hashed,
            totalCandidates: candidates.count,
            clustersSoFar: sorted.count
        ))

        Log.cluster.info("Stage 3: \(hashed) hashed → \(sorted.count) exact-duplicate clusters")
        return sorted
    }
}

/// Snapshot of the scan pipeline's state; emitted on a callback so UIs can render progress
/// without poking into the engine internals.
public struct ScanProgress: Sendable, Hashable {
    public enum Phase: String, Sendable, Hashable {
        case walking
        case indexing       // building the Photos lookup index (cold-cache hash of every lookup-source file)
        case hashing
        case done
    }

    public let phase: Phase
    public let filesSeen: Int
    public let filesHashed: Int
    public let totalCandidates: Int
    public let clustersSoFar: Int

    public init(phase: Phase, filesSeen: Int, filesHashed: Int, totalCandidates: Int, clustersSoFar: Int) {
        self.phase = phase
        self.filesSeen = filesSeen
        self.filesHashed = filesHashed
        self.totalCandidates = totalCandidates
        self.clustersSoFar = clustersSoFar
    }
}
