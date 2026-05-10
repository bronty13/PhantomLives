import XCTest
import CoreGraphics
@testable import PurpleDedupCore

final class VideoClustererTests: XCTestCase {

    func testIdenticalSequencesProduceZeroDistance() {
        let a = VideoFingerprint(
            frameHashes: [0x1, 0x2, 0x3, 0x4, 0x5],
            durationSeconds: 5, width: 320, height: 240, sampleRate: 1.0
        )
        let dist = VideoClusterer().bestAlignedMeanDistance(a, a)
        XCTAssertEqual(dist, 0)
    }

    func testCompletelyDifferentSequencesAreFar() {
        // hashes whose Hamming distance from each other is high
        let a = VideoFingerprint(
            frameHashes: [0x0000_0000_0000_0000, 0x0000_0000_0000_0000, 0x0000_0000_0000_0000, 0x0000_0000_0000_0000],
            durationSeconds: 4, width: 320, height: 240, sampleRate: 1.0
        )
        let b = VideoFingerprint(
            frameHashes: [0xFFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFF],
            durationSeconds: 4, width: 320, height: 240, sampleRate: 1.0
        )
        let dist = VideoClusterer().bestAlignedMeanDistance(a, b)
        XCTAssertEqual(dist, 64, "All-ones vs all-zeros = 64-bit Hamming distance")
    }

    func testAlignmentRecoversOffsetSequence() {
        // B is A shifted right by 2 frames (e.g. an intro was clipped).
        let common: [UInt64] = [0x100, 0x200, 0x300, 0x400, 0x500, 0x600, 0x700, 0x800]
        let a = VideoFingerprint(
            frameHashes: common,
            durationSeconds: 8, width: 320, height: 240, sampleRate: 1.0
        )
        let b = VideoFingerprint(
            frameHashes: [0x999, 0xAAA] + common,
            durationSeconds: 10, width: 320, height: 240, sampleRate: 1.0
        )
        let dist = VideoClusterer().bestAlignedMeanDistance(a, b)
        XCTAssertEqual(dist, 0, "A perfect 2-frame offset must be discovered by the alignment window")
    }

    /// The bounded sliding window only goes ±5; a 30-second clipped intro
    /// (≈8 frames at 1 fps capped at 12) is beyond it. Smith-Waterman picks
    /// up the alignment because it isn't bounded by a window — the matrix
    /// finds the best contiguous run wherever it lies.
    func testSmithWatermanRecoversFarOffset() {
        // B has 8 frames of unrelated content prepended before the shared
        // run — well outside the ±5 sliding window.
        let common: [UInt64] = [0x100, 0x200, 0x300, 0x400, 0x500, 0x600, 0x700, 0x800]
        let prefix: [UInt64] = [
            0xFFFF_0001, 0xFFFF_0002, 0xFFFF_0003, 0xFFFF_0004,
            0xFFFF_0005, 0xFFFF_0006, 0xFFFF_0007, 0xFFFF_0008,
        ]
        let a = VideoFingerprint(
            frameHashes: common,
            durationSeconds: 8, width: 320, height: 240, sampleRate: 1.0
        )
        let b = VideoFingerprint(
            frameHashes: prefix + common,
            durationSeconds: 16, width: 320, height: 240, sampleRate: 1.0
        )
        let dist = VideoClusterer().bestAlignedMeanDistance(a, b)
        XCTAssertEqual(dist, 0,
            "Smith-Waterman must recover an 8-frame offset that lies outside the sliding window")
    }

    func testDurationGateExcludesVeryDifferentLengths() {
        // Identical bytes but durations 1:5 → outside the 0.5..2.0 ratio band.
        let a_files = [makeFile(named: "a.mov", size: 1000)]
        let b_files = [makeFile(named: "b.mov", size: 1000)]
        let common: [UInt64] = [0x100, 0x100]
        let entries: [(DiscoveredFile, VideoFingerprint)] = [
            (a_files[0], VideoFingerprint(frameHashes: common, durationSeconds: 2, width: 320, height: 240, sampleRate: 1.0)),
            (b_files[0], VideoFingerprint(frameHashes: common, durationSeconds: 30, width: 320, height: 240, sampleRate: 1.0)),
        ]
        let clusters = VideoClusterer().clusterSimilar(entries: entries, threshold: 6)
        XCTAssertEqual(clusters.count, 0, "Duration ratio outside [0.5, 2.0] must reject the pair")
    }

    func testSimilarSequencesCluster() {
        // Two videos with byte-identical fingerprints: must cluster.
        let common: [UInt64] = [0x1, 0x2, 0x3, 0x4]
        let entries: [(DiscoveredFile, VideoFingerprint)] = [
            (makeFile(named: "a.mov", size: 1_000_000),
             VideoFingerprint(frameHashes: common, durationSeconds: 4, width: 320, height: 240, sampleRate: 1.0)),
            (makeFile(named: "b.mov", size: 500_000),
             VideoFingerprint(frameHashes: common, durationSeconds: 4, width: 320, height: 240, sampleRate: 1.0)),
        ]
        let clusters = VideoClusterer().clusterSimilar(entries: entries, threshold: 6)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.first?.files.count, 2)
        XCTAssertEqual(clusters.first?.maxPairwiseMeanDistance, 0)
    }

    func testExclusionByURL() {
        let common: [UInt64] = [0x1, 0x2, 0x3, 0x4]
        let a = makeFile(named: "a.mov", size: 1000)
        let b = makeFile(named: "b.mov", size: 1000)
        let entries: [(DiscoveredFile, VideoFingerprint)] = [
            (a, VideoFingerprint(frameHashes: common, durationSeconds: 4, width: 320, height: 240, sampleRate: 1.0)),
            (b, VideoFingerprint(frameHashes: common, durationSeconds: 4, width: 320, height: 240, sampleRate: 1.0)),
        ]
        let clusters = VideoClusterer().clusterSimilar(
            entries: entries, threshold: 6,
            excluding: [a.url]
        )
        XCTAssertEqual(clusters.count, 0,
            "Excluding one of the two members must collapse the cluster (need ≥2)")
    }

    private func makeFile(named name: String, size: Int64) -> DiscoveredFile {
        DiscoveredFile(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            sizeBytes: size,
            modificationTime: Date(timeIntervalSince1970: 0),
            isLocked: false
        )
    }
}
