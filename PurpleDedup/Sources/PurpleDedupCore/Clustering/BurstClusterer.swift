import Foundation

/// Groups photos taken within a small time window of each other AND within a
/// wider perceptual-similarity threshold than the regular `PerceptualClusterer`.
///
/// Targets the iPhone rapid-fire pattern: a user takes 10 shots of the same kid
/// running across the yard, picks the best one, and wants the other 9 dumped.
/// Those frames are *adjacent in time* and *visually related* but each is a
/// distinct photo — too different for the strict pHash threshold (≤6) to
/// cluster, but obviously a "burst" once you look at the capture timestamps.
///
/// Algorithm (simple and works well in practice):
///   1. Sort by capture date.
///   2. Walk a sliding window: photos i and i+1 are in the same candidate burst
///      if `|t_i+1 − t_i| ≤ windowSeconds`. Build runs of consecutive
///      same-burst photos.
///   3. Within each run, group photos by pHash proximity using union-find with
///      a wider threshold (`burstThreshold`, default 16 bits). Members with
///      shared neighbours land in the same cluster; isolated photos drop out.
///   4. Emit clusters of size ≥2.
public struct BurstClusterer: Sendable {

    /// Default time window for grouping rapid-fire captures. 3 seconds covers
    /// iPhone burst mode (10 shots/sec) with margin, while staying tight
    /// enough that distinct moments (a second photo of the same scene 30s
    /// later) don't get false-grouped.
    public static let defaultWindowSeconds: TimeInterval = 3.0

    /// Default Hamming-distance threshold for the burst-internal pHash check.
    /// Looser than the regular perceptual threshold (6) because adjacent burst
    /// frames are deliberately slightly different — that's the whole point of
    /// burst mode.
    public static let defaultThreshold: Int = 16

    public struct Entry: Sendable {
        public let file: DiscoveredFile
        public let captureDate: Date
        public let phash: UInt64

        public init(file: DiscoveredFile, captureDate: Date, phash: UInt64) {
            self.file = file
            self.captureDate = captureDate
            self.phash = phash
        }
    }

    public struct Cluster: Sendable {
        public let files: [DiscoveredFile]
        public let captureDateRange: ClosedRange<Date>
        public let maxPairwiseDistance: Int

        public init(files: [DiscoveredFile], captureDateRange: ClosedRange<Date>, maxPairwiseDistance: Int) {
            self.files = files
            self.captureDateRange = captureDateRange
            self.maxPairwiseDistance = maxPairwiseDistance
        }

        public var totalReclaimableBytes: Int64 {
            // Same accounting as similar-photo clusters: keep the largest one,
            // the rest is reclaimable. The smart-select rule chain produces
            // the actual keeper at decision time.
            guard let largest = files.map(\.sizeBytes).max() else { return 0 }
            return files.reduce(Int64(0)) { $0 + $1.sizeBytes } - largest
        }

        public var durationSeconds: TimeInterval {
            captureDateRange.upperBound.timeIntervalSince(captureDateRange.lowerBound)
        }
    }

    public init() {}

    public func clusterBursts(
        entries: [Entry],
        windowSeconds: TimeInterval = defaultWindowSeconds,
        threshold: Int = defaultThreshold,
        excluding excludeURLs: Set<URL> = []
    ) -> [Cluster] {
        let pool = entries.filter { !excludeURLs.contains($0.file.url) }
        guard pool.count >= 2 else { return [] }

        // Sort by capture date so we can walk in time order.
        let sorted = pool.sorted { $0.captureDate < $1.captureDate }

        // Step 1+2: build "time runs" — consecutive photos within `windowSeconds`
        // of their predecessor. Each run is a candidate burst.
        var runs: [[Entry]] = []
        var current: [Entry] = []
        for entry in sorted {
            if let last = current.last,
               entry.captureDate.timeIntervalSince(last.captureDate) <= windowSeconds {
                current.append(entry)
            } else {
                if current.count >= 2 { runs.append(current) }
                current = [entry]
            }
        }
        if current.count >= 2 { runs.append(current) }

        // Step 3: per-run perceptual clustering. We use union-find on pairwise
        // pHash similarity inside the run; this lets a series like A→A→B→B
        // (two distinct subjects in one rapid time window) split into two
        // clusters rather than collapse into one wrong group.
        var output: [Cluster] = []
        for run in runs {
            var uf = UnionFind(count: run.count)
            for i in 0..<run.count {
                for j in (i + 1)..<run.count {
                    let d = PerceptualHash.hammingDistance(run[i].phash, run[j].phash)
                    if d <= threshold {
                        uf.union(i, j)
                    }
                }
            }
            // Bucket by union-find root.
            var groups: [Int: [Int]] = [:]
            for i in 0..<run.count { groups[uf.find(i), default: []].append(i) }
            for indices in groups.values where indices.count >= 2 {
                let members = indices.map { run[$0] }
                let dates = members.map(\.captureDate)
                let minDate = dates.min()!
                let maxDate = dates.max()!

                // Diameter — for the cluster info card. O(k²) but k is small.
                var maxDist = 0
                for x in 0..<members.count {
                    for y in (x + 1)..<members.count {
                        let d = PerceptualHash.hammingDistance(members[x].phash, members[y].phash)
                        if d > maxDist { maxDist = d }
                    }
                }

                output.append(Cluster(
                    files: members.map(\.file).sorted { $0.url.path < $1.url.path },
                    captureDateRange: minDate...maxDate,
                    maxPairwiseDistance: maxDist
                ))
            }
        }

        // Sort: largest reclaimable first, ties by start time so equal-size
        // bursts read in chronological order.
        return output.sorted {
            if $0.totalReclaimableBytes != $1.totalReclaimableBytes {
                return $0.totalReclaimableBytes > $1.totalReclaimableBytes
            }
            return $0.captureDateRange.lowerBound < $1.captureDateRange.lowerBound
        }
    }
}
