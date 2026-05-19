import XCTest
@testable import PurpleReel

/// Coverage for the C23 edge-fade clamp helper
/// (`CombineClipsJob.clampEdgeFadeSeconds(_:edgeClipDuration:)`).
/// Same pure-helper testability pattern as the C20 cross-fade clamp:
/// the integration with `AVMutableVideoComposition` /
/// `AVMutableAudioMix` is left to manual QA, but the math that
/// decides "how much edge fade survives a too-short clip" sits in a
/// pure function so the rule is unambiguous.
final class EdgeFadeTests: XCTestCase {

    func testZeroRequestStaysZero() {
        XCTAssertEqual(
            CombineClipsJob.clampEdgeFadeSeconds(0, edgeClipDuration: 10),
            0
        )
    }

    func testNegativeRequestClampsToZero() {
        XCTAssertEqual(
            CombineClipsJob.clampEdgeFadeSeconds(-3, edgeClipDuration: 10),
            0
        )
    }

    func testRequestUnderEdgeDurationPassesThrough() {
        XCTAssertEqual(
            CombineClipsJob.clampEdgeFadeSeconds(2, edgeClipDuration: 10),
            2, accuracy: 0.0001
        )
    }

    func testRequestExceedingEdgeDurationClampsToEdgeDuration() {
        // Asking for a 12-second fade-in on a 4-second clip clamps
        // to 4 seconds — the fade can be at most the whole edge
        // clip. Allowing more would consume into the next clip's
        // territory, which is the cross-fade region's job, not the
        // edge fade's.
        XCTAssertEqual(
            CombineClipsJob.clampEdgeFadeSeconds(12, edgeClipDuration: 4),
            4, accuracy: 0.0001
        )
    }

    func testRequestExactlyEdgeDurationPassesThrough() {
        XCTAssertEqual(
            CombineClipsJob.clampEdgeFadeSeconds(5, edgeClipDuration: 5),
            5, accuracy: 0.0001
        )
    }

    func testZeroEdgeClipDurationClampsToZero() {
        // Degenerate but possible — caller passes 0 when there are
        // no sources. Clamp returns 0 so the rest of the run pass
        // takes the no-fade path without an extra guard.
        XCTAssertEqual(
            CombineClipsJob.clampEdgeFadeSeconds(2, edgeClipDuration: 0),
            0
        )
    }

    func testNegativeEdgeClipDurationClampsToZero() {
        // Shouldn't happen in practice (durations come from
        // AVAsset.load(.duration) and the pre-pass rejects negative
        // trimmed durations) but verify the guard.
        XCTAssertEqual(
            CombineClipsJob.clampEdgeFadeSeconds(2, edgeClipDuration: -1),
            0
        )
    }
}
