import XCTest
@testable import PurpleReel

/// Coverage for the C20 cross-fade math in
/// `CombineClipsJob.clampCrossfadeSeconds(...)` and `combinedOffsets(...)`.
/// Both are `nonisolated static` pure helpers so the rules are
/// testable without spinning up the actual AVAssetExportSession +
/// AVMutableVideoComposition + AVMutableAudioMix machinery; integration
/// is covered by manual QA.
final class CombineCrossfadeTests: XCTestCase {

    // MARK: clampCrossfadeSeconds

    func testZeroRequestedStaysZero() {
        XCTAssertEqual(
            CombineClipsJob.clampCrossfadeSeconds(
                0, trimmedDurations: [10, 10, 10]
            ), 0
        )
    }

    func testNegativeRequestedClampsToZero() {
        XCTAssertEqual(
            CombineClipsJob.clampCrossfadeSeconds(
                -3, trimmedDurations: [10, 10]
            ), 0
        )
    }

    func testSingleSourceClampsToZero() {
        // Nothing to fade between — clamp returns 0 so the service
        // takes the hard-cut path even with a non-zero request.
        XCTAssertEqual(
            CombineClipsJob.clampCrossfadeSeconds(
                2, trimmedDurations: [10]
            ), 0
        )
    }

    func testEmptyDurationsClampsToZero() {
        XCTAssertEqual(
            CombineClipsJob.clampCrossfadeSeconds(
                2, trimmedDurations: []
            ), 0
        )
    }

    func testRequestUnderHalfShortestPassesThrough() {
        // Shortest is 6s → half = 3s → 2s request fits.
        XCTAssertEqual(
            CombineClipsJob.clampCrossfadeSeconds(
                2, trimmedDurations: [10, 6, 8]
            ), 2, accuracy: 0.0001
        )
    }

    func testRequestExceedingHalfShortestClampsToHalfShortest() {
        // Shortest is 4s → half = 2s → 10s request clamps to 2s.
        XCTAssertEqual(
            CombineClipsJob.clampCrossfadeSeconds(
                10, trimmedDurations: [10, 4, 8]
            ), 2, accuracy: 0.0001
        )
    }

    func testRequestExactlyHalfShortestPassesThrough() {
        XCTAssertEqual(
            CombineClipsJob.clampCrossfadeSeconds(
                5, trimmedDurations: [10, 10, 10]
            ), 5, accuracy: 0.0001
        )
    }

    // MARK: combinedOffsets

    func testOffsetsWithoutCrossfadeIsCumulativeSum() {
        // cf=0 matches the pre-C20 hard-cut cursor: 0, 10, 20.
        let offsets = CombineClipsJob.combinedOffsets(
            trimmedDurations: [10, 10, 10], crossfade: 0
        )
        XCTAssertEqual(offsets, [0, 10, 20])
    }

    func testOffsetsWithCrossfadeReducesBySingleCFPerIndex() {
        // dur 10/10/10 with cf=2: offset[0]=0, offset[1]=10 - 1*2 = 8,
        // offset[2]=20 - 2*2 = 16. Each successive clip starts cf
        // earlier than its hard-cut position.
        let offsets = CombineClipsJob.combinedOffsets(
            trimmedDurations: [10, 10, 10], crossfade: 2
        )
        XCTAssertEqual(offsets, [0, 8, 16])
    }

    func testOffsetsHandleHeterogeneousDurations() {
        // 4 / 8 / 6, cf=1:
        // offset[0]=0
        // offset[1]=4 - 1*1 = 3
        // offset[2]=12 - 2*1 = 10
        let offsets = CombineClipsJob.combinedOffsets(
            trimmedDurations: [4, 8, 6], crossfade: 1
        )
        XCTAssertEqual(offsets, [0, 3, 10])
    }

    func testTotalOutputDurationFromOffsetsAndDurations() {
        // n clips, total = sum(durs) - (n-1)*cf.
        // dur 10/10/10, cf=2: 30 - 4 = 26.
        // Last clip's offset is 16; last clip's duration is 10;
        // tail = 16 + 10 = 26.
        let durs = [10.0, 10.0, 10.0]
        let cf = 2.0
        let offsets = CombineClipsJob.combinedOffsets(
            trimmedDurations: durs, crossfade: cf
        )
        let tail = offsets.last! + durs.last!
        XCTAssertEqual(tail, 26.0, accuracy: 0.0001)
    }

    func testEmptyDurationsYieldEmptyOffsets() {
        XCTAssertTrue(
            CombineClipsJob.combinedOffsets(
                trimmedDurations: [], crossfade: 1
            ).isEmpty
        )
    }

    func testSingleClipOffsetIsZero() {
        XCTAssertEqual(
            CombineClipsJob.combinedOffsets(
                trimmedDurations: [10], crossfade: 2
            ),
            [0]
        )
    }
}
