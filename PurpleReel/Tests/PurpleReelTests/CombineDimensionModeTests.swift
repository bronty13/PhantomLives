import XCTest
import CoreGraphics
@testable import PurpleReel

/// Coverage for the C19 canvas-size policy resolver in
/// `CombineClipsJob.resolveTargetSize(mode:sourceSizes:)`. Like the
/// C17 marker helper, this is pulled out as a `nonisolated static`
/// function so the rules are testable without AVAssetExportSession.
final class CombineDimensionModeTests: XCTestCase {

    func testFirstClipReturnsFirstSize() {
        let sizes: [CGSize] = [
            CGSize(width: 1280, height: 720),
            CGSize(width: 1920, height: 1080),
            CGSize(width: 3840, height: 2160),
        ]
        XCTAssertEqual(
            CombineClipsJob.resolveTargetSize(mode: .firstClip,
                                               sourceSizes: sizes),
            CGSize(width: 1280, height: 720)
        )
    }

    func testFirstClipWithEmptySourcesReturnsNil() {
        XCTAssertNil(
            CombineClipsJob.resolveTargetSize(mode: .firstClip,
                                               sourceSizes: [])
        )
    }

    func testLargestSourcePicksMaxWidthAndHeightIndependently() {
        // 1920×1080 wide and 1080×1920 tall together → 1920×1920
        // square that pillarboxes both. Documents the "no
        // downscaling, accept black bars" trade-off in the resolver.
        let sizes: [CGSize] = [
            CGSize(width: 1920, height: 1080),
            CGSize(width: 1080, height: 1920),
        ]
        XCTAssertEqual(
            CombineClipsJob.resolveTargetSize(mode: .largestSource,
                                               sourceSizes: sizes),
            CGSize(width: 1920, height: 1920)
        )
    }

    func testLargestSourcePicksMaxAcrossHomogeneousSet() {
        let sizes: [CGSize] = [
            CGSize(width: 1280, height: 720),
            CGSize(width: 1920, height: 1080),
            CGSize(width: 3840, height: 2160),
        ]
        XCTAssertEqual(
            CombineClipsJob.resolveTargetSize(mode: .largestSource,
                                               sourceSizes: sizes),
            CGSize(width: 3840, height: 2160)
        )
    }

    func testLargestSourceWithEmptySourcesReturnsNil() {
        XCTAssertNil(
            CombineClipsJob.resolveTargetSize(mode: .largestSource,
                                               sourceSizes: [])
        )
    }

    func testExplicitReturnsRequestedSize() {
        let result = CombineClipsJob.resolveTargetSize(
            mode: .explicit(width: 1920, height: 1080),
            sourceSizes: [CGSize(width: 720, height: 480)]
        )
        XCTAssertEqual(result, CGSize(width: 1920, height: 1080))
    }

    func testExplicitWithNonPositiveDimensionsReturnsNil() {
        // 0 or negative WxH would emerge from a typo in the
        // sheet's TextField. resolver guards rather than
        // returning a zero-sized canvas that AVAssetExportSession
        // would barf on later. The sheet's `resolvedDimensionMode`
        // separately falls back to `.firstClip` for the same case.
        XCTAssertNil(
            CombineClipsJob.resolveTargetSize(
                mode: .explicit(width: 0, height: 1080),
                sourceSizes: [CGSize(width: 1920, height: 1080)]
            )
        )
        XCTAssertNil(
            CombineClipsJob.resolveTargetSize(
                mode: .explicit(width: 1920, height: -1),
                sourceSizes: [CGSize(width: 1920, height: 1080)]
            )
        )
    }

    func testExplicitIgnoresSourceSizes() {
        // .explicit takes precedence over any source measurements
        // — the user has explicitly asked for a specific canvas.
        let result = CombineClipsJob.resolveTargetSize(
            mode: .explicit(width: 1280, height: 720),
            sourceSizes: [
                CGSize(width: 3840, height: 2160),
                CGSize(width: 7680, height: 4320),
            ]
        )
        XCTAssertEqual(result, CGSize(width: 1280, height: 720))
    }
}
