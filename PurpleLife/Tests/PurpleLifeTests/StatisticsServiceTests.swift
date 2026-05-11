import XCTest
@testable import PurpleLife

/// Pure-math coverage for the ported StatisticsService. The math is
/// the load-bearing part of slice 3b — the panel + chart overlays
/// just render what comes out of these functions.
///
/// Test data: synthetic series with known slopes / endpoints, so
/// we can predict the expected output without re-implementing the
/// math in the assertion.
final class StatisticsServiceTests: XCTestCase {

    private func date(_ daysAgo: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    }

    private func ascendingSeries(slopePerDay: Double, days: Int, start: Double = 200) -> [(date: Date, value: Double)] {
        (0..<days).map { i in
            (date: date(days - 1 - i), value: start + slopePerDay * Double(i))
        }
    }

    // MARK: - Linear regression

    func testLinearRegressionRecoversKnownSlope() {
        // 30-day perfectly linear loss: slope = -0.2 lb/day
        let series = ascendingSeries(slopePerDay: -0.2, days: 30)
        let (slope, r2) = StatisticsService.linearRegression(sorted: series)
        XCTAssertNotNil(slope)
        XCTAssertEqual(slope!, -0.2, accuracy: 0.001, "linear data should recover its slope exactly")
        XCTAssertEqual(r2!, 1.0, accuracy: 0.001, "linear data should give R² = 1")
    }

    func testLinearRegressionReturnsNilForFewerThanThreePoints() {
        let series: [(date: Date, value: Double)] = [(date(2), 200), (date(0), 199)]
        let (slope, r2) = StatisticsService.linearRegression(sorted: series)
        XCTAssertNil(slope)
        XCTAssertNil(r2)
    }

    // MARK: - Moving average

    func testMovingAverage7SmoothsRecentValues() {
        // 14 days flat at 180, then 7 days at 178
        let series: [(date: Date, value: Double)] = (0..<21).map {
            (date: date(20 - $0), value: $0 < 14 ? 180 : 178)
        }
        let ma7 = StatisticsService.movingAverage(sorted: series, window: 7)
        XCTAssertEqual(ma7.count, 21 - 7 + 1, "7-day MA produces N - window + 1 points")
        // Last MA value is the mean of the last 7 points (all 178)
        XCTAssertEqual(ma7.last!.value, 178, accuracy: 0.001)
        // First MA value is the mean of days 0-6 (all 180)
        XCTAssertEqual(ma7.first!.value, 180, accuracy: 0.001)
    }

    func testMovingAverageEmptyWhenWindowExceedsData() {
        let series = ascendingSeries(slopePerDay: -0.1, days: 5)
        let ma = StatisticsService.movingAverage(sorted: series, window: 30)
        XCTAssertTrue(ma.isEmpty)
    }

    // MARK: - BMI / forecast / days-to-goal — via compute

    func testComputeProducesBMIWhenHeightIsSet() {
        let series = ascendingSeries(slopePerDay: 0, days: 5, start: 150)  // 150 lb flat
        // Height 70 in = 1.778 m → BMI = 150 * 0.453592 / 1.778² ≈ 21.5
        let stats = StatisticsService.compute(
            points: series,
            goalWeightPounds: nil,
            startingWeightPounds: nil,
            heightInches: 70,
            forecastDays: 30
        )
        XCTAssertNotNil(stats)
        XCTAssertEqual(stats!.bmi!, 21.5, accuracy: 0.5)
    }

    func testComputeBMINilWhenHeightUnset() {
        let series = ascendingSeries(slopePerDay: 0, days: 5)
        let stats = StatisticsService.compute(
            points: series,
            goalWeightPounds: nil,
            startingWeightPounds: nil,
            heightInches: nil,
            forecastDays: 30
        )
        XCTAssertNotNil(stats)
        XCTAssertNil(stats!.bmi, "BMI requires height")
    }

    func testDaysToGoalAtKnownSlope() {
        // Current 200, goal 180, slope -0.5 lb/day → 40 days
        let days = StatisticsService.computeDaysToGoal(current: 200, goal: 180, slope: -0.5)
        XCTAssertEqual(days, 40)
    }

    func testDaysToGoalNilWhenSlopePositive() {
        // Slope positive (gaining) → can't extrapolate to a lower goal
        let days = StatisticsService.computeDaysToGoal(current: 200, goal: 180, slope: 0.3)
        XCTAssertNil(days)
    }

    func testDaysToGoalZeroWhenAlreadyPast() {
        let days = StatisticsService.computeDaysToGoal(current: 175, goal: 180, slope: -0.2)
        XCTAssertEqual(days, 0)
    }

    func testForecastExtrapolatesLinearly() {
        let series = ascendingSeries(slopePerDay: -0.3, days: 10, start: 200)
        let forecast = StatisticsService.forecastData(sorted: series, slope: -0.3, days: 5)
        XCTAssertEqual(forecast.count, 5)
        // Day 1 forecast = last_value + slope * 1
        let expectedDay1 = series.last!.value - 0.3
        XCTAssertEqual(forecast.first!.value, expectedDay1, accuracy: 0.001)
        // Day 5 forecast = last_value + slope * 5
        let expectedDay5 = series.last!.value - 0.3 * 5
        XCTAssertEqual(forecast.last!.value, expectedDay5, accuracy: 0.001)
    }

    // MARK: - Compute aggregate

    func testComputeReturnsNilForFewerThanTwoPoints() {
        let stats = StatisticsService.compute(
            points: [(date(0), 200)],
            goalWeightPounds: 180,
            startingWeightPounds: nil,
            heightInches: nil,
            forecastDays: 30
        )
        XCTAssertNil(stats, "compute requires at least 2 points")
    }
}
