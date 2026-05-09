import Foundation

/// Groups files whose perceptual hashes are within a Hamming-distance threshold. Phase 2
/// matches on pHash only; dHash is stored on each file for future cross-checks. The
/// requirements doc suggests `≤6` for "very similar," `≤12` for "loosely similar."
public struct PerceptualClusterer: Sendable {

    public struct Cluster: Sendable {
        public let files: [DiscoveredFile]
        public let hashes: [PerceptualHash]
        /// Maximum pairwise pHash Hamming distance within the cluster — i.e., the
        /// "diameter." Smaller means more confident the cluster is real.
        public let maxPairwiseDistance: Int

        public init(files: [DiscoveredFile], hashes: [PerceptualHash], maxPairwiseDistance: Int) {
            self.files = files
            self.hashes = hashes
            self.maxPairwiseDistance = maxPairwiseDistance
        }

        public var totalReclaimableBytes: Int64 {
            // Same accounting as exact clusters: keep one, the rest is reclaimable. For
            // perceptual clusters this is a *potential* number — the user might want to
            // keep multiple variants (RAW + JPEG, original + edited). The smart-select
            // rule chain (Phase 5) is what turns this into actual deletions.
            guard let largest = files.map(\.sizeBytes).max() else { return 0 }
            let total = files.reduce(Int64(0)) { $0 + $1.sizeBytes }
            return total - largest
        }
    }

    /// Threshold semantics from the requirements doc:
    ///   ≤  6: very similar (recompressions, minor crops, mild edits)
    ///   ≤ 12: loosely similar (larger edits, format conversions)
    public static let defaultThreshold = 6

    public init() {}

    /// Cluster the supplied (file, hash) pairs at the given threshold. Files in any of
    /// the supplied `excludingFileIDs` set are skipped — used to drop files that the
    /// exact clusterer already grouped (no point flagging the same files twice as
    /// "similar"; they're already known identical).
    ///
    /// Order of returned clusters: largest reclaimable first, ties by smallest path for
    /// determinism.
    public func clusterSimilar(
        entries: [(DiscoveredFile, PerceptualHash)],
        threshold: Int = defaultThreshold,
        excluding excludeURLs: Set<URL> = []
    ) -> [Cluster] {
        let kept = entries.enumerated()
            .filter { !excludeURLs.contains($0.element.0.url) }
            .map { (index: $0.offset, file: $0.element.0, hash: $0.element.1) }

        guard kept.count >= 2 else {
            Log.cluster.info("Perceptual: \(kept.count) candidate(s) — nothing to cluster")
            return []
        }

        // Build a BK-tree on pHash; payload is the position in `kept`.
        var tree = BKTree<Int>()
        for (i, _, hash) in kept {
            tree.insert(hash.phash, payload: i)
        }

        var uf = UnionFind(count: kept.count)
        // The original index assigned by `kept` — needed to map BK-tree payloads back
        // into our local 0..<kept.count space.
        var localIndex: [Int: Int] = [:]
        for (local, entry) in kept.enumerated() {
            localIndex[entry.index] = local
        }

        for (local, _, hash) in kept.enumerated().map({ ($0.offset, $0.element.file, $0.element.hash) }) {
            let neighbors = tree.neighbors(of: hash.phash, withinDistance: threshold)
            for n in neighbors {
                guard let other = localIndex[n.payload], other != local else { continue }
                uf.union(local, other)
            }
        }

        var groups: [Int: [Int]] = [:]
        for local in 0..<kept.count {
            groups[uf.find(local), default: []].append(local)
        }

        var clusters: [Cluster] = []
        for indices in groups.values where indices.count >= 2 {
            let members = indices.map { kept[$0] }.sorted { $0.file.url.path < $1.file.url.path }
            let files = members.map(\.file)
            let hashes = members.map(\.hash)

            // Diameter: max pairwise Hamming distance on pHash. O(k²) but k is small
            // (clusters are typically 2-10 members).
            var maxDist = 0
            for i in 0..<hashes.count {
                for j in (i + 1)..<hashes.count {
                    let d = PerceptualHash.hammingDistance(hashes[i].phash, hashes[j].phash)
                    if d > maxDist { maxDist = d }
                }
            }

            clusters.append(Cluster(
                files: files,
                hashes: hashes,
                maxPairwiseDistance: maxDist
            ))
        }

        let sorted = clusters.sorted {
            if $0.totalReclaimableBytes != $1.totalReclaimableBytes {
                return $0.totalReclaimableBytes > $1.totalReclaimableBytes
            }
            return $0.files.first?.url.path ?? "" < $1.files.first?.url.path ?? ""
        }

        Log.cluster.info("Perceptual: \(kept.count) hashed → \(sorted.count) similar-photo cluster(s) at threshold \(threshold)")
        return sorted
    }
}
