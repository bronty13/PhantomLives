import XCTest
@testable import PurpleReel

/// Coverage for the C17 marker-preservation pass in
/// `CombineClipsJob.offsetMarkers(_:trimInSec:trimOutSec:cursorSec:)`.
/// The helper is pure (no AVAssetExportSession) so we can exercise
/// the filter + offset rules without spinning up a real export — the
/// service loop just calls this helper once per source and concatenates
/// the results, so coverage here exercises the load-bearing logic.
final class CombineSourceMarkerPreservationTests: XCTestCase {

    /// Marker entirely inside the trim window lands on the combined
    /// timeline at `cursor + (originalTC - trimIn)`.
    func testMarkerInsideRangeIsOffsetByCursor() {
        let m = Marker(id: 1, assetId: 10,
                       timecodeIn: 4.0, timecodeOut: 5.0,
                       note: "interesting", createdAt: Date())
        let result = CombineClipsJob.offsetMarkers(
            [m], trimInSec: 2.0, trimOutSec: 10.0, cursorSec: 30.0
        )
        XCTAssertEqual(result.count, 1)
        // 4s into a clip whose trim starts at 2s = 2s into the
        // trimmed segment. The segment starts at cursor 30s on the
        // combined timeline, so the marker should land at 32s.
        XCTAssertEqual(result[0].timecodeIn, 32.0, accuracy: 0.0001)
        XCTAssertEqual(result[0].timecodeOut ?? -1, 33.0, accuracy: 0.0001)
        XCTAssertEqual(result[0].note, "interesting")
    }

    /// Marker before the trim-in is dropped — it points at footage
    /// the user explicitly clipped off the front.
    func testMarkerBeforeTrimInIsDropped() {
        let m = Marker(id: 1, assetId: 10,
                       timecodeIn: 1.0, timecodeOut: nil,
                       note: nil, createdAt: Date())
        let result = CombineClipsJob.offsetMarkers(
            [m], trimInSec: 5.0, trimOutSec: 10.0, cursorSec: 0
        )
        XCTAssertTrue(result.isEmpty,
                      "Marker at 1s should drop when trim starts at 5s")
    }

    /// Marker after the trim-out is dropped — same reason on the
    /// trailing side.
    func testMarkerAfterTrimOutIsDropped() {
        let m = Marker(id: 1, assetId: 10,
                       timecodeIn: 11.0, timecodeOut: nil,
                       note: nil, createdAt: Date())
        let result = CombineClipsJob.offsetMarkers(
            [m], trimInSec: 5.0, trimOutSec: 10.0, cursorSec: 0
        )
        XCTAssertTrue(result.isEmpty,
                      "Marker at 11s should drop when trim ends at 10s")
    }

    /// Marker whose `timecodeIn` is inside the window but whose
    /// `timecodeOut` extends past the trim-out: the start survives
    /// and the out is clamped to the window's end so the output
    /// doesn't carry a marker pointing past the combined timeline.
    func testMarkerOutPastTrimOutIsClamped() {
        let m = Marker(id: 1, assetId: 10,
                       timecodeIn: 8.0, timecodeOut: 15.0,
                       note: "long range", createdAt: Date())
        let result = CombineClipsJob.offsetMarkers(
            [m], trimInSec: 5.0, trimOutSec: 10.0, cursorSec: 100.0
        )
        XCTAssertEqual(result.count, 1)
        // 8s in a segment trimmed from [5,10] sits at offset 3s →
        // combined timeline 103s. The 15s out clamps to the trim's
        // 10s end → offset 5s → combined 105s.
        XCTAssertEqual(result[0].timecodeIn, 103.0, accuracy: 0.0001)
        XCTAssertEqual(result[0].timecodeOut ?? -1, 105.0, accuracy: 0.0001)
    }

    /// Empty trim range (trimOut <= trimIn) returns no markers —
    /// matches the service's `state = .failed` guard for empty
    /// ranges. Safe to ask for the offset even though the loop won't
    /// actually call here on the empty-range path.
    func testEmptyRangeYieldsNothing() {
        let m = Marker(id: 1, assetId: 10,
                       timecodeIn: 1.0, timecodeOut: nil,
                       note: nil, createdAt: Date())
        XCTAssertTrue(CombineClipsJob.offsetMarkers(
            [m], trimInSec: 5.0, trimOutSec: 5.0, cursorSec: 0
        ).isEmpty)
        XCTAssertTrue(CombineClipsJob.offsetMarkers(
            [m], trimInSec: 10.0, trimOutSec: 5.0, cursorSec: 0
        ).isEmpty)
    }

    /// Marker exactly at the trim-in / trim-out boundary is kept.
    /// (Inclusive on both sides — the segment renders that frame, so
    /// the marker on that frame should ride along.)
    func testMarkerExactlyOnBoundariesIsKept() {
        let inMarker = Marker(id: 1, assetId: 10,
                              timecodeIn: 5.0, timecodeOut: nil,
                              note: "at-in", createdAt: Date())
        let outMarker = Marker(id: 2, assetId: 10,
                               timecodeIn: 10.0, timecodeOut: nil,
                               note: "at-out", createdAt: Date())
        let result = CombineClipsJob.offsetMarkers(
            [inMarker, outMarker],
            trimInSec: 5.0, trimOutSec: 10.0, cursorSec: 50.0
        )
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.note), ["at-in", "at-out"])
        XCTAssertEqual(result[0].timecodeIn, 50.0, accuracy: 0.0001)
        XCTAssertEqual(result[1].timecodeIn, 55.0, accuracy: 0.0001)
    }

    /// Whole-clip path (nil trim → service substitutes 0 / duration)
    /// — verify a marker keeps its absolute position when cursor=0
    /// and trim-in=0. This is the most common case: combining
    /// whole clips with markers should land them at their natural
    /// times on the combined output.
    func testWholeClipPathPreservesAbsolutePositions() {
        let m1 = Marker(id: 1, assetId: 10, timecodeIn: 2.5,
                        timecodeOut: nil, note: "a", createdAt: Date())
        let m2 = Marker(id: 2, assetId: 10, timecodeIn: 7.5,
                        timecodeOut: nil, note: "b", createdAt: Date())
        let result = CombineClipsJob.offsetMarkers(
            [m1, m2], trimInSec: 0, trimOutSec: 10.0, cursorSec: 0
        )
        XCTAssertEqual(result.map(\.timecodeIn), [2.5, 7.5])
    }
}
