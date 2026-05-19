import XCTest
@testable import PurpleReel

/// Coverage for the C24 per-pair cross-fade math. Replaces the C20
/// global-scalar path with per-pair values so each clip can carry its
/// own override (`CombineSource.crossfadeAfterSeconds`). Two pure
/// helpers carry the load:
///
///   - `clampPerPairCrossfades(perPairRequested:globalDefault:trimmedDurations:)`
///     — resolves each pair's requested fade against `min(durs[i],
///     durs[i+1]) / 2`, filling in nils from the global default.
///
///   - `combinedOffsetsPerPair(trimmedDurations:perPairCrossfades:)`
///     — subtracts running cross-fade total from each clip's start.
final class PerPairCrossfadeTests: XCTestCase {

    // MARK: clampPerPairCrossfades

    func testEmptyDurationsReturnEmpty() {
        XCTAssertTrue(
            CombineClipsJob.clampPerPairCrossfades(
                perPairRequested: [],
                globalDefault: 2,
                trimmedDurations: []
            ).isEmpty
        )
    }

    func testSingleClipReturnEmpty() {
        // Nothing to fade between.
        XCTAssertTrue(
            CombineClipsJob.clampPerPairCrossfades(
                perPairRequested: [nil],
                globalDefault: 2,
                trimmedDurations: [10]
            ).isEmpty
        )
    }

    func testAllNilFillsFromGlobalDefault() {
        let result = CombineClipsJob.clampPerPairCrossfades(
            perPairRequested: [nil, nil, nil],
            globalDefault: 2,
            trimmedDurations: [10, 10, 10]
        )
        XCTAssertEqual(result, [2, 2])
    }

    func testOverridesWinOverGlobalDefault() {
        // Pair 0 gets the override (3); pair 1 falls through to
        // global (1).
        let result = CombineClipsJob.clampPerPairCrossfades(
            perPairRequested: [3, nil, nil],
            globalDefault: 1,
            trimmedDurations: [10, 10, 10]
        )
        XCTAssertEqual(result, [3, 1])
    }

    func testEachPairClampedToHalfOfMinNeighbor() {
        // durs = 10, 4, 8.
        // pair 0 (between 10 and 4): half-min = 2 → clamp 10 → 2.
        // pair 1 (between 4 and 8): half-min = 2 → clamp 10 → 2.
        let result = CombineClipsJob.clampPerPairCrossfades(
            perPairRequested: [10, 10],
            globalDefault: 0,
            trimmedDurations: [10, 4, 8]
        )
        XCTAssertEqual(result, [2, 2], "Each pair clamps independently to half-of-min-neighbor")
    }

    func testZeroOverrideStaysZeroEvenWithNonzeroGlobal() {
        // Explicit 0 override = "no fade after this clip", not
        // "use global". This is how a user mixes one cross-fade
        // section with a hard cut.
        let result = CombineClipsJob.clampPerPairCrossfades(
            perPairRequested: [0, nil],
            globalDefault: 2,
            trimmedDurations: [10, 10, 10]
        )
        XCTAssertEqual(result, [0, 2])
    }

    func testNegativeOverrideClampsToZero() {
        let result = CombineClipsJob.clampPerPairCrossfades(
            perPairRequested: [-5, nil],
            globalDefault: 1,
            trimmedDurations: [10, 10, 10]
        )
        XCTAssertEqual(result, [0, 1])
    }

    // MARK: combinedOffsetsPerPair

    func testOffsetsAllZeroDegeneratesToCumulativeSum() {
        // No fades → same as hard-cut cursor.
        let offsets = CombineClipsJob.combinedOffsetsPerPair(
            trimmedDurations: [10, 10, 10],
            perPairCrossfades: [0, 0]
        )
        XCTAssertEqual(offsets, [0, 10, 20])
    }

    func testOffsetsUniformCrossfadeMatchesC20Math() {
        // [3, 3] uniform should match the C20 helper:
        // offset[0] = 0, offset[1] = 10 - 3 = 7, offset[2] = 20 - 6 = 14.
        let offsets = CombineClipsJob.combinedOffsetsPerPair(
            trimmedDurations: [10, 10, 10],
            perPairCrossfades: [3, 3]
        )
        XCTAssertEqual(offsets, [0, 7, 14])
    }

    func testOffsetsMixedPerPairCrossfadesAccumulate() {
        // 5 / 7 / 3 with cf 2 / 0 between them:
        // offset[0]=0, offset[1]=5-2=3, offset[2]=12-2=10.
        let offsets = CombineClipsJob.combinedOffsetsPerPair(
            trimmedDurations: [5, 7, 3],
            perPairCrossfades: [2, 0]
        )
        XCTAssertEqual(offsets, [0, 3, 10])
    }

    func testEmptyOffsetsForEmptyInput() {
        XCTAssertTrue(
            CombineClipsJob.combinedOffsetsPerPair(
                trimmedDurations: [], perPairCrossfades: []
            ).isEmpty
        )
    }

    func testSingleClipOffsetIsZero() {
        XCTAssertEqual(
            CombineClipsJob.combinedOffsetsPerPair(
                trimmedDurations: [10], perPairCrossfades: []
            ),
            [0]
        )
    }
}
