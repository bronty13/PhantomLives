import Foundation

struct WeightStats {
    var totalChange: Double          // positive = gain, negative = loss
    var lastEntryChange: Double?
    var averageWeeklyChange: Double? // rolling 4-week
    var bestWeek: (start: String, loss: Double)?
    var worstWeek: (start: String, gain: Double)?
    var movingAverage7: [(date: String, value: Double)]
    var movingAverage30: [(date: String, value: Double)]
    var regressionSlope: Double?     // lbs/day (negative = losing)
    var regressionR2: Double?
    var forecastData: [(date: String, value: Double)]
    var daysToGoal: Int?
    var bmi: Double?
    var startingBMI: Double?
    var goalBMI: Double?
    var startWeight: Double
    var currentWeight: Double
    var goalWeight: Double?
    var percentToGoal: Double?
}

struct StatisticsService {
    static func compute(
        entries: [WeightEntry],
        settings: AppSettings
    ) -> WeightStats? {
        guard entries.count >= 2 else { return nil }
        let sorted = entries.sorted { $0.date < $1.date }

        let startWeight: Double
        if let sw = settings.startingWeight {
            startWeight = sw
        } else {
            startWeight = sorted.first!.weightLbs
        }
        let currentWeight = sorted.last!.weightLbs
        let totalChange = currentWeight - startWeight

        let lastEntryChange: Double? = sorted.count >= 2
            ? sorted.last!.weightLbs - sorted[sorted.count - 2].weightLbs
            : nil

        let avgWeeklyChange = computeAverageWeeklyChange(sorted: sorted, weeks: 4)
        let (bestWeek, worstWeek) = computeBestWorstWeek(sorted: sorted)
        let ma7 = movingAverage(sorted: sorted, window: 7)
        let ma30 = movingAverage(sorted: sorted, window: 30)
        let (slope, r2) = linearRegression(sorted: sorted)
        let forecast = forecastData(sorted: sorted, slope: slope, days: settings.forecastDays)
        let daysToGoal = computeDaysToGoal(current: currentWeight, goal: settings.goalWeight, slope: slope)

        let heightM: Double? = settings.heightInches.map { $0 * 0.0254 }
        let bmi = heightM.map { h in (currentWeight * 0.453592) / (h * h) }
        let startingBMI = heightM.map { h in (startWeight * 0.453592) / (h * h) }
        let goalBMI = settings.goalWeight.flatMap { gw in heightM.map { h in (gw * 0.453592) / (h * h) } }

        let percentToGoal: Double? = settings.goalWeight.map { goal in
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
            goalWeight: settings.goalWeight,
            percentToGoal: percentToGoal
        )
    }

    private static func computeAverageWeeklyChange(sorted: [WeightEntry], weeks: Int) -> Double? {
        guard sorted.count >= 2 else { return nil }
        let cutoff = Calendar.current.date(byAdding: .weekOfYear, value: -weeks, to: Date()) ?? Date()
        let cutoffStr = iso(cutoff)
        let recent = sorted.filter { $0.date >= cutoffStr }
        guard recent.count >= 2 else {
            let days = daysBetween(sorted.first!.date, sorted.last!.date)
            guard days > 0 else { return nil }
            return (sorted.last!.weightLbs - sorted.first!.weightLbs) / (Double(days) / 7)
        }
        let days = daysBetween(recent.first!.date, recent.last!.date)
        guard days > 0 else { return nil }
        return (recent.last!.weightLbs - recent.first!.weightLbs) / (Double(days) / 7)
    }

    private static func computeBestWorstWeek(sorted: [WeightEntry]) -> (
        best: (start: String, loss: Double)?,
        worst: (start: String, gain: Double)?
    ) {
        guard sorted.count >= 2 else { return (nil, nil) }
        var best: (start: String, loss: Double)? = nil
        var worst: (start: String, gain: Double)? = nil

        for i in 0..<sorted.count - 1 {
            let a = sorted[i]
            let b = sorted[i + 1]
            let days = daysBetween(a.date, b.date)
            guard days > 0 && days <= 14 else { continue }
            let weeklyRate = (b.weightLbs - a.weightLbs) / (Double(days) / 7)
            let loss = -weeklyRate
            if best == nil || loss > best!.loss { best = (a.date, loss) }
            if worst == nil || loss < worst!.gain { worst = (a.date, loss) }
        }
        return (best, worst.map { (start: $0.start, gain: $0.gain) })
    }

    static func movingAverage(sorted: [WeightEntry], window: Int) -> [(date: String, value: Double)] {
        guard sorted.count >= window else { return [] }
        var result: [(date: String, value: Double)] = []
        for i in (window - 1)..<sorted.count {
            let slice = sorted[(i - window + 1)...i]
            let avg = slice.map { $0.weightLbs }.reduce(0, +) / Double(window)
            result.append((date: sorted[i].date, value: avg))
        }
        return result
    }

    static func linearRegression(sorted: [WeightEntry]) -> (slope: Double?, r2: Double?) {
        guard sorted.count >= 3 else { return (nil, nil) }
        let ref = sorted.first!.date
        let xs = sorted.map { Double(daysBetween(ref, $0.date)) }
        let ys = sorted.map { $0.weightLbs }
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

    private static func forecastData(sorted: [WeightEntry], slope: Double?, days: Int) -> [(date: String, value: Double)] {
        guard let slope, let last = sorted.last, let lastDate = last.parsedDate else { return [] }
        let cal = Calendar.current
        var result: [(date: String, value: Double)] = []
        for d in 1...days {
            guard let future = cal.date(byAdding: .day, value: d, to: lastDate) else { continue }
            let forecastWeight = last.weightLbs + slope * Double(d)
            result.append((date: iso(future), value: forecastWeight))
        }
        return result
    }

    private static func computeDaysToGoal(current: Double, goal: Double?, slope: Double?) -> Int? {
        guard let goal, let slope, slope < 0 else { return nil }
        let needed = current - goal
        guard needed > 0 else { return 0 }
        return Int(ceil(needed / (-slope)))
    }

    static func daysBetween(_ a: String, _ b: String) -> Int {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        guard let da = fmt.date(from: a), let db = fmt.date(from: b) else { return 0 }
        return Calendar.current.dateComponents([.day], from: da, to: db).day ?? 0
    }

    private static func iso(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }
}
