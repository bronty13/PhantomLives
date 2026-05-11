import Foundation

/// Pure-math statistics over a `(date, value)` time series. Input arg
/// is type-agnostic so the same service can serve any future numeric
/// type, but BMI specifically is weight-shaped (kg / m²).
///
/// Ported from `WeightTracker/Sources/WeightTracker/Services/StatisticsService.swift`.
/// Differences from the original:
/// - Input is `[(date: Date, value: Double)]` not `[WeightEntry]` —
///   keeps the math reusable.
/// - Uses `Date` arithmetic instead of "yyyy-MM-dd" string ↔ `Date`
///   round-trips. Cleaner, less locale-fragile.
/// - Returns nil from `compute` when fewer than 2 points are available;
///   linear regression additionally requires ≥3 points.
struct WeightStats {
    var totalChange: Double                 // positive = gain, negative = loss
    var lastEntryChange: Double?
    var averageWeeklyChange: Double?        // rolling 4-week
    var bestWeek: (start: Date, loss: Double)?
    var worstWeek: (start: Date, gain: Double)?
    var movingAverage7: [(date: Date, value: Double)]
    var movingAverage30: [(date: Date, value: Double)]
    var regressionSlope: Double?            // value-units / day (negative = decreasing)
    var regressionR2: Double?
    var forecastData: [(date: Date, value: Double)]
    var daysToGoal: Int?
    var bmi: Double?
    var startingBMI: Double?
    var goalBMI: Double?
    var startWeight: Double
    var currentWeight: Double
    var goalWeight: Double?
    var percentToGoal: Double?
}

enum StatisticsService {

    /// Compute the full statistics bundle from a sorted-or-unsorted
    /// time series + the four AppSettings profile values that drive
    /// goal / starting / BMI / forecast. Returns nil if there isn't
    /// enough data (< 2 points) to say anything meaningful.
    static func compute(
        points: [(date: Date, value: Double)],
        goalWeightPounds: Double?,
        startingWeightPounds: Double?,
        heightInches: Double?,
        forecastDays: Int
    ) -> WeightStats? {
        guard points.count >= 2 else { return nil }
        let sorted = points.sorted { $0.date < $1.date }

        let startWeight = startingWeightPounds ?? sorted.first!.value
        let currentWeight = sorted.last!.value
        let totalChange = currentWeight - startWeight

        let lastEntryChange: Double? = sorted.count >= 2
            ? sorted.last!.value - sorted[sorted.count - 2].value
            : nil

        let avgWeeklyChange = computeAverageWeeklyChange(sorted: sorted, weeks: 4)
        let (bestWeek, worstWeek) = computeBestWorstWeek(sorted: sorted)
        let ma7 = movingAverage(sorted: sorted, window: 7)
        let ma30 = movingAverage(sorted: sorted, window: 30)
        let (slope, r2) = linearRegression(sorted: sorted)
        let forecast = forecastData(sorted: sorted, slope: slope, days: forecastDays)
        let daysToGoal = computeDaysToGoal(current: currentWeight, goal: goalWeightPounds, slope: slope)

        let heightM: Double? = heightInches.map { $0 * 0.0254 }
        let bmi = heightM.map { h in (currentWeight * 0.453592) / (h * h) }
        let startingBMI = heightM.map { h in (startWeight * 0.453592) / (h * h) }
        let goalBMI = goalWeightPounds.flatMap { gw in heightM.map { h in (gw * 0.453592) / (h * h) } }

        let percentToGoal: Double? = goalWeightPounds.map { goal in
            guard totalChange != 0 else { return 0 }
            let needed = startWeight - goal
            let achieved = startWeight - currentWeight
            guard needed != 0 else { return 100 }
            return min(100, max(0, (achieved / needed) * 100))
        }

        return WeightStats(
            totalChange: totalChange,
            lastEntryChange: lastEntryChange,
            averageWeeklyChange: avgWeeklyChange,
            bestWeek: bestWeek,
            worstWeek: worstWeek,
            movingAverage7: ma7,
            movingAverage30: ma30,
            regressionSlope: slope,
            regressionR2: r2,
            forecastData: forecast,
            daysToGoal: daysToGoal,
            bmi: bmi,
            startingBMI: startingBMI,
            goalBMI: goalBMI,
            startWeight: startWeight,
            currentWeight: currentWeight,
            goalWeight: goalWeightPounds,
            percentToGoal: percentToGoal
        )
    }

    // MARK: - Components (each independently testable)

    /// Average per-week change over the last `weeks` weeks. Falls back
    /// to "all data" if there aren't enough recent points.
    static func computeAverageWeeklyChange(
        sorted: [(date: Date, value: Double)],
        weeks: Int
    ) -> Double? {
        guard sorted.count >= 2 else { return nil }
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -weeks, to: Date()) ?? Date()
        let recent = sorted.filter { $0.date >= cutoff }
        let span = recent.count >= 2 ? recent : sorted
        let days = daysBetween(span.first!.date, span.last!.date)
        guard days > 0 else { return nil }
        return (span.last!.value - span.first!.value) / (Double(days) / 7)
    }

    /// Walk consecutive entries, compute the per-week rate between
    /// each pair of points whose date gap is 1-14 days. Best week
    /// = largest negative rate (biggest weekly loss); worst week =
    /// largest positive rate (biggest weekly gain).
    static func computeBestWorstWeek(
        sorted: [(date: Date, value: Double)]
    ) -> (best: (start: Date, loss: Double)?, worst: (start: Date, gain: Double)?) {
        guard sorted.count >= 2 else { return (nil, nil) }
        var best: (start: Date, loss: Double)? = nil
        var worst: (start: Date, gain: Double)? = nil

        for i in 0..<sorted.count - 1 {
            let a = sorted[i]
            let b = sorted[i + 1]
            let days = daysBetween(a.date, b.date)
            guard days > 0, days <= 14 else { continue }
            let weeklyRate = (b.value - a.value) / (Double(days) / 7)
            let loss = -weeklyRate
            if best == nil || loss > best!.loss { best = (a.date, loss) }
            if worst == nil || loss < worst!.gain { worst = (a.date, loss) }
        }
        return (best, worst.map { (start: $0.start, gain: $0.gain) })
    }

    /// Simple moving average over `window` consecutive entries
    /// (NOT a calendar-day window — matches WeightTracker behavior).
    static func movingAverage(
        sorted: [(date: Date, value: Double)],
        window: Int
    ) -> [(date: Date, value: Double)] {
        guard sorted.count >= window, window > 0 else { return [] }
        var result: [(date: Date, value: Double)] = []
        for i in (window - 1)..<sorted.count {
            let slice = sorted[(i - window + 1)...i]
            let avg = slice.map(\.value).reduce(0, +) / Double(window)
            result.append((date: sorted[i].date, value: avg))
        }
        return result
    }

    /// Least-squares linear regression in (days-since-first, value)
    /// space. Returns (slope_value_per_day, R²). Both nil when
    /// `sorted.count < 3` or when X variance is zero (all points on
    /// the same day).
    static func linearRegression(
        sorted: [(date: Date, value: Double)]
    ) -> (slope: Double?, r2: Double?) {
        guard sorted.count >= 3 else { return (nil, nil) }
        let ref = sorted.first!.date
        let xs = sorted.map { Double(daysBetween(ref, $0.date)) }
        let ys = sorted.map(\.value)
        let n = Double(sorted.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumX2 = xs.map { $0 * $0 }.reduce(0, +)
        let denom = n * sumX2 - sumX * sumX
        guard denom != 0 else { return (nil, nil) }
        let slope = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n
        let meanY = sumY / n
        let ssTot = ys.map { ($0 - meanY) * ($0 - meanY) }.reduce(0, +)
        let ssRes: Double = zip(xs, ys).reduce(0.0) { acc, pair in
            let pred = slope * pair.0 + intercept
            let diff = pair.1 - pred
            return acc + diff * diff
        }
        let r2 = ssTot > 0 ? 1 - ssRes / ssTot : 1
        return (slope, r2)
    }

    /// Linear extrapolation: `last_value + slope * d` for each future
    /// day in `1...days`. Returns empty when slope is nil.
    static func forecastData(
        sorted: [(date: Date, value: Double)],
        slope: Double?,
        days: Int
    ) -> [(date: Date, value: Double)] {
        guard let slope, let last = sorted.last, days > 0 else { return [] }
        let cal = Calendar.current
        var result: [(date: Date, value: Double)] = []
        for d in 1...days {
            guard let future = cal.date(byAdding: .day, value: d, to: last.date) else { continue }
            let value = last.value + slope * Double(d)
            result.append((date: future, value: value))
        }
        return result
    }

    /// Estimated days to reach goal, given a negative slope (i.e.
    /// weight is decreasing). Returns nil if there's no goal, no
    /// slope, or the slope is non-negative (going wrong direction).
    /// Returns 0 if already at-or-past the goal.
    static func computeDaysToGoal(current: Double, goal: Double?, slope: Double?) -> Int? {
        guard let goal, let slope, slope < 0 else { return nil }
        let needed = current - goal
        guard needed > 0 else { return 0 }
        return Int(ceil(needed / (-slope)))
    }

    // MARK: - Helpers

    static func daysBetween(_ a: Date, _ b: Date) -> Int {
        Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
    }
}

// MARK: - Adapter from ObjectRecord → (date, value)

extension StatisticsService {

    /// Convenience wrapper for the Weight type — extracts `(date,
    /// pounds)` from records and dispatches to `compute`. Skips
    /// records missing either field. The chart code in
    /// `RecordsChartBody` does the same extraction; we don't share
    /// the helper to keep StatisticsService independent of
    /// view-layer concerns.
    static func computeForWeightRecords(
        _ rows: [ObjectRecord],
        settings: AppSettings
    ) -> WeightStats? {
        let points: [(date: Date, value: Double)] = rows.compactMap { r in
            let f = r.fields()
            guard let d = parseISODate(f["date"]),
                  let v = numericValue(f["pounds"]) else { return nil }
            return (d, v)
        }
        return compute(
            points: points,
            goalWeightPounds: settings.goalWeightPounds,
            startingWeightPounds: settings.startingWeightPounds,
            heightInches: settings.heightInches,
            forecastDays: settings.forecastDays
        )
    }

    private static func parseISODate(_ raw: Any?) -> Date? {
        guard let s = raw as? String else { return nil }
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    private static func numericValue(_ raw: Any?) -> Double? {
        guard let raw, !(raw is NSNull) else { return nil }
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        if let s = raw as? String { return Double(s) }
        return nil
    }
}
