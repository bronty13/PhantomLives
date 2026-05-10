import Foundation

/// Groups files whose perceptual hashes are within a Hamming-distance threshold.
/// Two photos cluster together if **either** their pHash distance OR their dHash
/// distance is within the threshold (OR-of-distances). pHash and dHash catch
/// different transformation classes — pHash tracks the low-frequency DCT profile
/// (recompressions, mild edits), dHash tracks the local gradient direction (small
/// crops, slight rotations / brightness shifts). OR-merging tightens recall on
/// real-world libraries without lowering precision: pure-noise pairs almost never
/// happen to land near each other under both hash families.
///
/// The requirements doc suggests `≤6` for "very similar," `≤12` for "loosely similar."
public struct PerceptualClusterer: Sendable {

    public struct Cluster: Sendable {
        public let files: [DiscoveredFile]
        public let hashes: [PerceptualHash]
        /// Cluster "diameter" — `min(pHash diameter, dHash diameter)`. Under
        /// OR-of-distances clustering a cluster can be joined entirely through
        /// one of the two hash families; reporting the minimum reflects the
        /// tightest bound under either, which is the more meaningful confidence
        /// signal. Smaller means more confident the cluster is real.
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

        // Two BK-trees: one keyed on pHash, one on dHash. Payload is the local position
        // in `kept`. A neighbor in EITHER tree merges the two members in union-find,
        // implementing the OR-of-distances semantics described in the type docs.
        var pTree = BKTree<Int>()
        var dTree = BKTree<Int>()
        for (i, _, hash) in kept {
            pTree.insert(hash.phash, payload: i)
            dTree.insert(hash.dhash, payload: i)
        }

        var uf = UnionFind(count: kept.count)
        // The original index assigned by `kept` — needed to map BK-tree payloads back
        // into our local 0..<kept.count space.
        var localIndex: [Int: Int] = [:]
        for (local, entry) in kept.enumerated() {
            localIndex[entry.index] = local
        }

        for (local, _, hash) in kept.enumerated().map({ ($0.offset, $0.element.file, $0.element.hash) }) {
            for n in pTree.neighbors(of: hash.phash, withinDistance: threshold) {
                guard let other = localIndex[n.payload], other != local else { continue }
                uf.union(local, other)
            }
            for n in dTree.neighbors(of: hash.dhash, withinDistance: threshold) {
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

            // Diameter: `min(pHash diameter, dHash diameter)`. O(k²) but k is small
            // (clusters are typically 2-10 members).
            var maxP = 0, maxD = 0
            for i in 0..<hashes.count {
                for j in (i + 1)..<hashes.count {
                    let dp = PerceptualHash.hammingDistance(hashes[i].phash, hashes[j].phash)
                    if dp > maxP { maxP = dp }
                    let dd = PerceptualHash.hammingDistance(hashes[i].dhash, hashes[j].dhash)
                    if dd > maxD { maxD = dd }
                }
            }
            let maxDist = min(maxP, maxD)

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
