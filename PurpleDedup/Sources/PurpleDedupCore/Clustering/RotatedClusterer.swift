import Foundation

/// Groups photos that are exact-content duplicates of each other under a 90°
/// rotation (FR-2.7). The signature is the four-hash array
/// `[pHash(0°), pHash(90°), pHash(180°), pHash(270°)]` — two files are
/// rotation-duplicates if *any* of one's four hashes is within `threshold`
/// Hamming distance of *any* of the other's four. The 0° pair already gets
/// caught by the regular perceptual clusterer; this surfaces the other 12
/// pair-orientations the regular pass misses.
///
/// Pairwise O(n²) over 16 hash comparisons. For typical libraries (low
/// thousands of photos) this is <1s; for tens of thousands of photos a
/// per-rotation BK-tree would be the next step but isn't worth the code
/// complexity at the current scale.
public struct RotatedClusterer: Sendable {

    /// Default Hamming-distance threshold. Tighter than the regular
    /// perceptual default (6) because rotation should be a near-exact match
    /// — the same image, just turned. Looser bands would let true
    /// "different-but-similar" pairs sneak in here when they belong in
    /// `similar_photo` instead.
    public static let defaultThreshold: Int = 4

    public struct Entry: Sendable {
        public let file: DiscoveredFile
        /// pHashes at 0°, 90°, 180°, 270° in that order.
        public let rotationHashes: [UInt64]

        public init(file: DiscoveredFile, rotationHashes: [UInt64]) {
            self.file = file
            self.rotationHashes = rotationHashes
        }
    }

    public struct Cluster: Sendable {
        public let files: [DiscoveredFile]
        public let maxPairwiseDistance: Int
        /// The rotation between cluster member 0 and each other member, in
        /// degrees (0 / 90 / 180 / 270). Element i corresponds to files[i];
        /// element 0 is always 0. Useful for the comparison view to show
        /// "this one is rotated 90° relative to the keeper."
        public let rotationsRelativeToFirst: [Int]

        public init(files: [DiscoveredFile], maxPairwiseDistance: Int, rotationsRelativeToFirst: [Int]) {
            self.files = files
            self.maxPairwiseDistance = maxPairwiseDistance
            self.rotationsRelativeToFirst = rotationsRelativeToFirst
        }

        public var totalReclaimableBytes: Int64 {
            guard let largest = files.map(\.sizeBytes).max() else { return 0 }
            return files.reduce(Int64(0)) { $0 + $1.sizeBytes } - largest
        }
    }

    public init() {}

    public func clusterRotated(
        entries: [Entry],
        threshold: Int = defaultThreshold,
        excluding excludeURLs: Set<URL> = []
    ) -> [Cluster] {
        let kept = entries.filter { !excludeURLs.contains($0.file.url) }
        guard kept.count >= 2 else { return [] }

        var uf = UnionFind(count: kept.count)
        // For each connected pair, record the rotation offset (in 90° units)
        // between them. We anchor every cluster's first member at rotation
        // 0; subsequent members' rotations are derived along the union path.
        // For rendering we only need the rotation relative to the first
        // member — propagating these offsets lazily through union-find is
        // overkill, so we recompute at output time below.
        for i in 0..<kept.count {
            for j in (i + 1)..<kept.count {
                if rotationDistance(kept[i].rotationHashes, kept[j].rotationHashes) <= threshold {
                    uf.union(i, j)
                }
            }
        }

        var groups: [Int: [Int]] = [:]
        for i in 0..<kept.count {
            groups[uf.find(i), default: []].append(i)
        }

        var clusters: [Cluster] = []
        for indices in groups.values where indices.count >= 2 {
            let members = indices.map { kept[$0] }.sorted { $0.file.url.path < $1.file.url.path }
            let files = members.map(\.file)

            // Rotation offsets relative to the first member: find the
            // rotation k for each subsequent member j such that hash(0°, member 0)
            // is closest to hash(k, member j). The k that minimises is the
            // member's relative rotation.
            let baseHashes = members[0].rotationHashes
            var rotations: [Int] = [0]
            for j in 1..<members.count {
                let theirHashes = members[j].rotationHashes
                var bestK = 0
                var bestDist = 65
                for k in 0..<4 {
                    let d = PerceptualHash.hammingDistance(baseHashes[0], theirHashes[k])
                    if d < bestDist { bestDist = d; bestK = k }
                }
                rotations.append(bestK * 90)
            }

            // Diameter — max pairwise rotation-distance across all members.
            var maxDist = 0
            for x in 0..<members.count {
                for y in (x + 1)..<members.count {
                    let d = rotationDistance(members[x].rotationHashes, members[y].rotationHashes)
                    if d > maxDist { maxDist = d }
                }
            }

            clusters.append(Cluster(
                files: files,
                maxPairwiseDistance: maxDist,
                rotationsRelativeToFirst: rotations
            ))
        }

        return clusters.sorted {
            if $0.totalReclaimableBytes != $1.totalReclaimableBytes {
                return $0.totalReclaimableBytes > $1.totalReclaimableBytes
            }
            return $0.files.first?.url.path ?? "" < $1.files.first?.url.path ?? ""
        }
    }

    /// Smallest Hamming distance between any rotation of A and any rotation
    /// of B. 16 pairs total (4 × 4). Always returns 0…64.
    public func rotationDistance(_ a: [UInt64], _ b: [UInt64]) -> Int {
        var best = Int.max
        for x in a {
            for y in b {
                let d = PerceptualHash.hammingDistance(x, y)
                if d < best { best = d }
            }
        }
        return best
    }
}
