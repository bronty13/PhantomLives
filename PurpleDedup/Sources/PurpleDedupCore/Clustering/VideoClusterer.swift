import Foundation

/// Groups videos whose perceptual fingerprints align closely enough at some offset.
///
///   For each candidate pair (A, B):
///     - Reject if duration ratio is outside [0.5, 2.0] (very different lengths can't
///       be the same video, even with intro/outro trimming).
///     - Compute `bestAlignedMeanDistance(A, B)` — see that method for the alignment
///       algorithm. The metric is mean per-frame Hamming distance over the best
///       alignment, scale matches the photo threshold (bits per 64-bit hash).
///     - Pair matches if mean ≤ threshold.
///
/// `bestAlignedMeanDistance` runs a cheap ±5-frame sliding window AND a Smith-Waterman
/// local alignment, returning the smaller of the two. The sliding window catches the
/// common case (re-encode drift, slightly clipped leaders) at near-zero cost; SW
/// handles videos with substantially-different leaders (a 30-second intro clipped,
/// different first scene) that the bounded window misses.
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

    /// Compute the smallest mean per-frame Hamming distance over the best alignment
    /// of two fingerprints. Two algorithms run; the lower mean wins:
    ///
    /// 1. **Bounded sliding window** (offsets ±`alignmentWindow`). Cheap; handles
    ///    typical re-encode drift and a few dropped leading frames.
    /// 2. **Smith-Waterman local alignment**. Allows the alignment to start at any
    ///    offset (not just within ±5) and tolerates small frame-sample-rate drift via
    ///    a gap penalty. Catches videos where one leader was substantially clipped
    ///    so the matching content begins mid-sequence in one of the two.
    ///
    /// SW is `O(M·N)` over the frame counts. Frame counts are capped at
    /// `VideoFingerprinter.maxFramesPerVideo` (12 today) so the matrix is at most
    /// 12×12 — comparable cost to the sliding window.
    public func bestAlignedMeanDistance(_ a: VideoFingerprint, _ b: VideoFingerprint) -> Int {
        guard !a.frameHashes.isEmpty, !b.frameHashes.isEmpty else { return Int.max }
        let sliding = slidingWindowMeanDistance(a.frameHashes, b.frameHashes)
        let sw = smithWatermanMeanDistance(a.frameHashes, b.frameHashes)
        return min(sliding, sw)
    }

    /// Bounded sliding-window mean Hamming distance. Tries every offset in
    /// `±alignmentWindow`, returns the smallest mean over the overlapping region
    /// (must cover ≥50% of the shorter sequence to count). Returns `Int.max` when
    /// no offset hits the overlap floor.
    private func slidingWindowMeanDistance(_ a: [UInt64], _ b: [UInt64]) -> Int {
        var bestMean = Int.max
        for offset in (-Self.alignmentWindow)...Self.alignmentWindow {
            var sum = 0
            var count = 0
            for i in 0..<a.count {
                let j = i + offset
                if j < 0 || j >= b.count { continue }
                sum += PerceptualHash.hammingDistance(a[i], b[j])
                count += 1
            }
            // Require enough overlap to be meaningful — at least 50% of the shorter
            // sequence. Otherwise a 1-frame "alignment" can score 0 and false-match.
            let minOverlap = max(1, min(a.count, b.count) / 2)
            if count >= minOverlap {
                let mean = sum / max(count, 1)
                if mean < bestMean { bestMean = mean }
            }
        }
        return bestMean
    }

    /// Smith-Waterman local alignment of two frame-hash sequences. Builds the standard
    /// 2D DP matrix with substitution score `(neutralPoint - hammingDistance)` per pair
    /// and a constant gap penalty, finds the highest-scoring cell, traces back through
    /// the matched-pair list, and returns the mean Hamming distance over those matches.
    /// Returns `Int.max` when no alignment of sufficient length exists.
    ///
    /// **Tuning:**
    /// - `neutralPoint = 16` makes substitutions positive when bits-of-difference is
    ///   under 16 (≈ similar) and negative above (≈ unrelated). The exact value tunes
    ///   how willing the algorithm is to extend a so-so match vs. start a fresh one.
    /// - `gapPenalty = 8` discourages skips; a single skipped frame costs more than a
    ///   moderately mismatched pair, so the algorithm prefers a contiguous diagonal
    ///   wherever possible. Allowing gaps at all matters because frame-sample-rate
    ///   drift produces near-misses where one frame in A best matches `b[j]` and the
    ///   next in A best matches `b[j+2]`.
    /// - `minOverlap` = half the shorter sequence, same gate as the sliding window —
    ///   prevents a single-frame "alignment" of unrelated videos from false-matching.
    private func smithWatermanMeanDistance(_ a: [UInt64], _ b: [UInt64]) -> Int {
        let M = a.count, N = b.count
        guard M > 0, N > 0 else { return Int.max }

        let neutralPoint = 16
        let gapPenalty = 8
        // Trace tags: which neighbour cell produced the cell's value.
        // `.stop` means the cell maxed at 0 (alignment terminus).
        enum Move: UInt8 { case stop, diagonal, up, left }

        var H = Array(repeating: Array(repeating: 0, count: N + 1), count: M + 1)
        var trace = Array(repeating: Array(repeating: Move.stop, count: N + 1), count: M + 1)

        var bestScore = 0
        var bestI = 0
        var bestJ = 0

        for i in 1...M {
            for j in 1...N {
                let h = PerceptualHash.hammingDistance(a[i - 1], b[j - 1])
                let sub  = H[i - 1][j - 1] + (neutralPoint - h)
                let up   = H[i - 1][j]     - gapPenalty
                let left = H[i][j - 1]     - gapPenalty
                let best = max(0, sub, up, left)
                H[i][j] = best
                if best == 0 { trace[i][j] = .stop }
                else if best == sub { trace[i][j] = .diagonal }
                else if best == up { trace[i][j] = .up }
                else { trace[i][j] = .left }
                if best > bestScore {
                    bestScore = best
                    bestI = i
                    bestJ = j
                }
            }
        }

        if bestScore == 0 { return Int.max }

        // Traceback from the best cell, accumulating per-pair Hamming distances on
        // diagonal moves only (up / left moves are gaps, contribute no pair).
        var matched: [Int] = []
        var i = bestI
        var j = bestJ
        while i > 0, j > 0, trace[i][j] != .stop, H[i][j] > 0 {
            switch trace[i][j] {
            case .diagonal:
                matched.append(PerceptualHash.hammingDistance(a[i - 1], b[j - 1]))
                i -= 1; j -= 1
            case .up:
                i -= 1
            case .left:
                j -= 1
            case .stop:
                i = 0; j = 0   // terminate the loop
            }
        }

        let minOverlap = max(1, min(M, N) / 2)
        if matched.count < minOverlap { return Int.max }
        return matched.reduce(0, +) / max(matched.count, 1)
    }
}
