import XCTest
@testable import PurpleReel

/// Coverage for the C27 eased-ramp helper. AVFoundation's
/// `setOpacityRamp` / `setVolumeRamp` are linear-only; we
/// approximate the four standard curves (linear / easeIn / easeOut
/// / easeInOut) via N piecewise-linear segments. Tests pin the
/// sample values + boundary behavior.
final class CrossfadeEasingTests: XCTestCase {

    // MARK: - Endpoint values

    /// Every curve must hit y=0 at t=0 and y=1 at t=1 for the
    /// fade-in direction. Otherwise the cross-fade doesn't fully
    /// resolve and the user sees a non-1.0 final opacity.
    func testFadeInEndpointsAreExactlyZeroAndOne() {
        for easing in [CrossfadeEasing.linear, .easeIn, .easeOut, .easeInOut] {
            let v = CombineClipsJob.easedRampValues(samples: 8,
                                                    easing: easing,
                                                    reversed: false)
            XCTAssertEqual(v.first ?? -1, 0, accuracy: 0.0001,
                            "\(easing) fade-in must start at 0")
            XCTAssertEqual(v.last ?? -1, 1, accuracy: 0.0001,
                            "\(easing) fade-in must end at 1")
        }
    }

    func testFadeOutEndpointsAreExactlyOneAndZero() {
        for easing in [CrossfadeEasing.linear, .easeIn, .easeOut, .easeInOut] {
            let v = CombineClipsJob.easedRampValues(samples: 8,
                                                    easing: easing,
                                                    reversed: true)
            XCTAssertEqual(v.first ?? -1, 1, accuracy: 0.0001,
                            "\(easing) fade-out must start at 1")
            XCTAssertEqual(v.last ?? -1, 0, accuracy: 0.0001,
                            "\(easing) fade-out must end at 0")
        }
    }

    // MARK: - Linear

    /// Linear should be exactly evenly-spaced — no curve at all.
    func testLinearGivesEvenlySpacedValues() {
        let v = CombineClipsJob.easedRampValues(samples: 4,
                                                 easing: .linear,
                                                 reversed: false)
        XCTAssertEqual(v.count, 5)  // N+1 samples
        XCTAssertEqual(v[0], 0.0, accuracy: 0.0001)
        XCTAssertEqual(v[1], 0.25, accuracy: 0.0001)
        XCTAssertEqual(v[2], 0.5, accuracy: 0.0001)
        XCTAssertEqual(v[3], 0.75, accuracy: 0.0001)
        XCTAssertEqual(v[4], 1.0, accuracy: 0.0001)
    }

    // MARK: - EaseIn (y = x²)

    /// EaseIn is slow at the start, fast at the end. At t=0.5 the
    /// linear value would be 0.5; easeIn gives 0.25 (= 0.5²).
    func testEaseInMidpointIsBelowLinear() {
        let v = CombineClipsJob.easedRampValues(samples: 2,
                                                 easing: .easeIn,
                                                 reversed: false)
        XCTAssertEqual(v[1], 0.25, accuracy: 0.0001,
                        "easeIn at t=0.5 should be 0.25, not 0.5")
    }

    func testEaseInIsMonotonicNonDecreasingForward() {
        let v = CombineClipsJob.easedRampValues(samples: 8,
                                                 easing: .easeIn,
                                                 reversed: false)
        for i in 0..<v.count - 1 {
            XCTAssertGreaterThanOrEqual(v[i + 1], v[i],
                                          "easeIn must be monotonic non-decreasing")
        }
    }

    // MARK: - EaseOut (y = 1 - (1-x)²)

    /// Mirror of EaseIn — fast at the start, slow at the end. At
    /// t=0.5 the linear value would be 0.5; easeOut gives 0.75.
    func testEaseOutMidpointIsAboveLinear() {
        let v = CombineClipsJob.easedRampValues(samples: 2,
                                                 easing: .easeOut,
                                                 reversed: false)
        XCTAssertEqual(v[1], 0.75, accuracy: 0.0001,
                        "easeOut at t=0.5 should be 0.75, not 0.5")
    }

    // MARK: - EaseInOut (smoothstep, y = 3x² - 2x³)

    /// EaseInOut is symmetric around t=0.5 → y=0.5. Apple's
    /// smoothstep formula (3x²-2x³) lands exactly there.
    func testEaseInOutMidpointIsExactlyHalf() {
        let v = CombineClipsJob.easedRampValues(samples: 2,
                                                 easing: .easeInOut,
                                                 reversed: false)
        XCTAssertEqual(v[1], 0.5, accuracy: 0.0001,
                        "easeInOut at t=0.5 should be 0.5 (smoothstep is symmetric)")
    }

    /// Quarter-point: 3(0.25)² - 2(0.25)³ = 0.1875 - 0.03125 = 0.15625
    func testEaseInOutQuarterPointIsBelowLinear() {
        let v = CombineClipsJob.easedRampValues(samples: 4,
                                                 easing: .easeInOut,
                                                 reversed: false)
        XCTAssertEqual(v[1], 0.15625, accuracy: 0.0001,
                        "easeInOut at t=0.25 should be ~0.156")
    }

    // MARK: - Sample count

    func testSamplesParameterControlsValueCount() {
        // N+1 values for N segments.
        for n in [1, 4, 8, 16] {
            let v = CombineClipsJob.easedRampValues(samples: n,
                                                     easing: .linear,
                                                     reversed: false)
            XCTAssertEqual(v.count, n + 1,
                            "samples=\(n) should yield \(n+1) values")
        }
    }

    /// Zero or negative samples clamp to N=1 (single ramp from 0 to 1
    /// — degenerate but valid; no zero-division at the caller).
    func testZeroOrNegativeSamplesClampToOne() {
        XCTAssertEqual(
            CombineClipsJob.easedRampValues(samples: 0,
                                             easing: .linear,
                                             reversed: false).count,
            2
        )
        XCTAssertEqual(
            CombineClipsJob.easedRampValues(samples: -3,
                                             easing: .linear,
                                             reversed: false).count,
            2
        )
    }
}
