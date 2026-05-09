import XCTest
@testable import PurpleDedupCore

final class BurstClustererTests: XCTestCase {

    func testEmptyInputProducesNoClusters() {
        XCTAssertTrue(BurstClusterer().clusterBursts(entries: []).isEmpty)
    }

    func testTwoSimilarPhotosSecondsApartCluster() {
        let entries = [
            entry(path: "/burst/a.jpg", offset: 0,   phash: 0xABCD_0001_0000_0000),
            entry(path: "/burst/b.jpg", offset: 0.3, phash: 0xABCD_0001_0000_0010), // 1 bit diff
            entry(path: "/burst/c.jpg", offset: 0.6, phash: 0xABCD_0001_0000_0100), // ~2 bits from start
        ]
        let clusters = BurstClusterer().clusterBursts(entries: entries)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.first?.files.count, 3)
    }

    func testPhotosOutsideTimeWindowDoNotCluster() {
        // Two visually identical photos but ten seconds apart — outside the
        // 3-second default window. Burst clusterer must NOT group them. The
        // regular perceptual matcher (different layer) would catch them.
        let entries = [
            entry(path: "/a.jpg", offset: 0,    phash: 0xDEADBEEF),
            entry(path: "/b.jpg", offset: 10.0, phash: 0xDEADBEEF),
        ]
        XCTAssertTrue(BurstClusterer().clusterBursts(entries: entries).isEmpty)
    }

    func testWidelyDifferentPhotosWithinWindowDoNotCluster() {
        // Same time burst, but visually distinct (32 bits apart, way past the
        // burst threshold of 16). Two unrelated subjects shot within 1 second.
        let entries = [
            entry(path: "/a.jpg", offset: 0.0, phash: 0x0000_0000_0000_0000),
            entry(path: "/b.jpg", offset: 0.5, phash: 0xFFFF_FFFF_0000_0000),
        ]
        XCTAssertTrue(BurstClusterer().clusterBursts(entries: entries).isEmpty)
    }

    func testTwoDistinctSubjectsInOneTimeRunSplitIntoTwoClusters() {
        // A→A→B→B in rapid succession — two subjects each photographed twice
        // within the burst window. Burst clusterer should produce TWO clusters,
        // not one.
        let entries = [
            entry(path: "/a1.jpg", offset: 0.0, phash: 0x1111_1111_1111_1111),
            entry(path: "/a2.jpg", offset: 0.3, phash: 0x1111_1111_1111_1112),
            entry(path: "/b1.jpg", offset: 0.6, phash: 0xCAFE_BABE_DEAD_BEEF),
            entry(path: "/b2.jpg", offset: 0.9, phash: 0xCAFE_BABE_DEAD_BEFF),
        ]
        let clusters = BurstClusterer().clusterBursts(entries: entries)
        XCTAssertEqual(clusters.count, 2)
        for c in clusters {
            XCTAssertEqual(c.files.count, 2)
        }
    }

    func testDateRangeReflectsFirstAndLastFrame() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            entry(path: "/a.jpg", offset: 0.0, phash: 0xABCD, baseDate: base),
            entry(path: "/b.jpg", offset: 1.5, phash: 0xABCD, baseDate: base),
        ]
        let cluster = BurstClusterer().clusterBursts(entries: entries).first!
        XCTAssertEqual(cluster.captureDateRange.lowerBound, base)
        XCTAssertEqual(cluster.captureDateRange.upperBound, base.addingTimeInterval(1.5))
        XCTAssertEqual(cluster.durationSeconds, 1.5, accuracy: 0.001)
    }

    func testExclusionByURL() {
        let entries = [
            entry(path: "/a.jpg", offset: 0.0, phash: 0xABCD),
            entry(path: "/b.jpg", offset: 0.3, phash: 0xABCD),
        ]
        let clusters = BurstClusterer().clusterBursts(
            entries: entries, excluding: [URL(fileURLWithPath: "/a.jpg")]
        )
        XCTAssertTrue(clusters.isEmpty,
            "Excluding one of the two members must collapse the cluster")
    }

    // MARK: - helpers

    private func entry(
        path: String,
        offset: TimeInterval,
        phash: UInt64,
        baseDate: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> BurstClusterer.Entry {
        let f = DiscoveredFile(
            url: URL(fileURLWithPath: path),
            sizeBytes: 1000,
            modificationTime: baseDate.addingTimeInterval(offset),
            isLocked: false
        )
        return BurstClusterer.Entry(
            file: f,
            captureDate: baseDate.addingTimeInterval(offset),
            phash: phash
        )
    }
}
