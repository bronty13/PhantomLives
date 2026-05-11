import XCTest
@testable import PurpleTracker

/// Variance + Y/Y math on the vendor Budget & Actuals matrix.
@MainActor
final class BudgetMathTests: XCTestCase {

    func testYoyNilWhenNoPriorYear() {
        XCTAssertNil(BudgetMath.yoyPercent(current: 10_000, prior: nil))
        XCTAssertEqual(BudgetMath.yoyDisplay(current: 10_000, prior: nil), "—")
    }

    func testYoyNilWhenPriorIsZero() {
        // No meaningful denominator; can't compute % growth from $0.
        XCTAssertNil(BudgetMath.yoyPercent(current: 10_000, prior: 0))
        XCTAssertEqual(BudgetMath.yoyDisplay(current: 10_000, prior: 0), "—")
    }

    func testYoyPositiveGrowth() {
        // 10,000 -> 12,500 cents = +25.0%
        let pct = BudgetMath.yoyPercent(current: 12_500, prior: 10_000)
        XCTAssertEqual(pct!, 25.0, accuracy: 0.0001)
        XCTAssertEqual(BudgetMath.yoyDisplay(current: 12_500, prior: 10_000), "+25.0%")
    }

    func testYoyNegativeGrowth() {
        // 10,000 -> 9,000 cents = -10.0%
        XCTAssertEqual(BudgetMath.yoyDisplay(current: 9_000, prior: 10_000), "-10.0%")
    }

    func testYoyFlat() {
        XCTAssertEqual(BudgetMath.yoyDisplay(current: 5_000, prior: 5_000), "0.0%")
    }

    func testVarianceSignAndFormat() {
        // Positive variance (under budget) uses Money formatting.
        XCTAssertEqual(BudgetMath.varianceDisplay(cents: 12_345), Money.format(cents: 12_345))
        // Negative variance (over budget) gets a leading minus.
        XCTAssertEqual(BudgetMath.varianceDisplay(cents: -12_345), "−" + Money.format(cents: 12_345))
        // Zero variance reads as $0.00.
        XCTAssertEqual(BudgetMath.varianceDisplay(cents: 0), Money.format(cents: 0))
    }
}
