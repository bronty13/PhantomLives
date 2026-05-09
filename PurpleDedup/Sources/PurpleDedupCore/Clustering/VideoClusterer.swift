import Foundation

/// Groups videos whose perceptual fingerprints align closely enough at some offset.
/// Phase 3 algorithm:
///
///   For each candidate pair (A, B):
///     - Reject if duration ratio is outside [0.5, 2.0] (very different lengths can't
///       be the same video, even with intro/outro trimming).
///     - Try a small set of frame offsets (-5..+5 frames). For each offset, compute the
///       mean per-frame Hamming distance over the overlapping region.
///     - Take the minimum mean across offsets. Pair matches if min ≤ threshold.
///
/// The ±5-frame window covers typical re-encode artefacts (slight clock drift, dropped
/// leading frames, codec keyframe placement). For longer offsets (a 30-second intro
/// clipped off) the simple sliding window is wrong; full sequence alignment via DP is
/// the Phase-7 enhancement.
public struct VideoClusterer: Sendable {

    public struct Cluster: Sendable {
        public let files: [DiscoveredFile]
        public let fingerprints: [VideoFingerprint]
        /// Maximum pairwise mean Hamming distance within the cluster — i.e., the
        /// "diameter" measured the same way pairs were screened. Lower = tighter match.
        public let maxPairwiseMeanDistance: Int

        public init(files: [DiscoveredFile], fingerprints: [VideoFingerprint], maxPairwiseMeanDistance: Int) {
            self.files = files
            self.fingerprints = fingerprints
            self.maxPairwiseMeanDistance = maxPairwiseMeanDistance
        }

        public var totalReclaimableBytes: Int64 {
            guard let largest = files.map(\.sizeBytes).max() else { return 0 }
            let total = files.reduce(Int64(0)) { $0 + $1.sizeBytes }
            return total - largest
        }
    }

    /// Same scale as the photo threshold: bits-of-difference per 64-bit hash, averaged
    /// over the aligned frame window. 6 = "very similar," 12 = "loosely similar."
    public static let defaultThreshold = 6

    /// Number of frame positions to slide before giving up. Balances false positives
    /// (very wide windows happily align unrelated content) against missed matches
    /// (clipped intros). 5 catches typical transcode drift.
    public static let alignmentWindow = 5

    /// Reject pairs whose duration ratio is outside this band — they can't be the
    /// same video even with intro/outro edits.
    public static let durationRatioMin = 0.5
    public static let durationRatioMax = 2.0

    public init() {}

    public func clusterSimilar(
        entries: [(DiscoveredFile, VideoFingerprint)],
        threshold: Int = defaultThreshold,
        excluding excludeURLs: Set<URL> = []
    ) -> [Cluster] {
        let kept = entries.enumerated()
            .filter { !excludeURLs.contains($0.element.0.url) }
            .map { (index: $0.offset, file: $0.element.0, fingerprint: $0.element.1) }

        guard kept.count >= 2 else {
            Log.cluster.info("Video: \(kept.count) candidate(s) — nothing to cluster")
            return []
        }

        var uf = UnionFind(count: kept.count)

        // Pairwise comparison. O(n²) on candidate count — fine up to a few hundred
        // videos, which is the vast majority of personal libraries. For larger
        // libraries we'd build per-frame BK-trees and only compare videos that share
        // ≥1 close-enough frame; deferred to Phase 7 if profiling shows it's needed.
        for i in 0..<kept.count {
            for j in (i + 1)..<kept.count {
                let a = kept[i].fingerprint
                let b = kept[j].fingerprint
                guard durationsAreComparable(a, b) else { continue }
                let mean = bestAlignedMeanDistance(a, b)
                if mean <= threshold {
                    uf.union(i, j)
                }
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
            let fps = members.map(\.fingerprint)

            // Diameter: max pairwise mean distance.
            var maxDist = 0
            for x in 0..<fps.count {
                for y in (x + 1)..<fps.count {
                    let d = bestAlignedMeanDistance(fps[x], fps[y])
                    if d > maxDist { maxDist = d }
                }
            }
            clusters.append(Cluster(files: files, fingerprints: fps, maxPairwiseMeanDistance: maxDist))
        }

        let sorted = clusters.sorted {
            if $0.totalReclaimableBytes != $1.totalReclaimableBytes {
                return $0.totalReclaimableBytes > $1.totalReclaimableBytes
            }
            return $0.files.first?.url.path ?? "" < $1.files.first?.url.path ?? ""
        }

        Log.cluster.info("Video: \(kept.count) fingerprinted → \(sorted.count) similar-video cluster(s) at threshold \(threshold)")
        return sorted
    }

    private func durationsAreComparable(_ a: VideoFingerprint, _ b: VideoFingerprint) -> Bool {
        guard a.durationSeconds > 0, b.durationSeconds > 0 else { return false }
        let ratio = a.durationSeconds / b.durationSeconds
        return ratio >= Self.durationRatioMin && ratio <= Self.durationRatioMax
    }

    /// Compute the smallest mean per-frame Hamming distance over the alignment window.
    /// `bestAlignedMeanDistance` is the metric the threshold compares against.
    public func bestAlignedMeanDistance(_ a: VideoFingerprint, _ b: VideoFingerprint) -> Int {
        guard !a.frameHashes.isEmpty, !b.frameHashes.isEmpty else { return Int.max }

        var bestMean = Int.max
        for offset in (-Self.alignmentWindow)...Self.alignmentWindow {
            var sum = 0
            var count = 0
            for i in 0..<a.frameHashes.count {
                let j = i + offset
                if j < 0 || j >= b.frameHashes.count { continue }
                sum += PerceptualHash.hammingDistance(a.frameHashes[i], b.frameHashes[j])
                count += 1
            }
            // Require enough overlap to be meaningful — at least 50% of the shorter
            // sequence. Otherwise a 1-frame "alignment" can score 0 and false-match.
            let minOverlap = max(1, min(a.frameHashes.count, b.frameHashes.count) / 2)
            if count >= minOverlap {
                let mean = sum / max(count, 1)
                if mean < bestMean { bestMean = mean }
            }
        }
        return bestMean
    }
}
