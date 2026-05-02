import SwiftUI
import Charts

struct ScatterChartView: View {
    @EnvironmentObject var appState: AppState
    var entries: [WeightEntry]

    private var unit: WeightUnit { appState.settings.weightUnit }
    private var accent: Color { appState.effectiveAccentColor }

    private var yDomain: ClosedRange<Double> {
        let weights = entries.map { $0.displayWeight(unit: unit) }
        guard let lo = weights.min(), let hi = weights.max(), lo < hi else { return 0...200 }
        let pad = (hi - lo) * 0.12
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        Chart {
            // Raw data points, color-coded by position in range
            ForEach(entries) { entry in
                if let date = entry.parsedDate {
                    let w = entry.displayWeight(unit: unit)
                    PointMark(
                        x: .value("Date", date),
                        y: .value("Weight", w)
                    )
                    .foregroundStyle(accent.opacity(0.75))
                    .symbolSize(28)
                    .symbol(.circle)
                }
            }

            // Regression line (full extent)
            if let stats = appState.stats, let slope = stats.regressionSlope {
                ForEach(regressionPoints(slope: slope), id: \.date) { pt in
                    if let date = parseDate(pt.date) {
                        LineMark(
                            x: .value("Date", date),
                            y: .value("Trend", pt.value.asUnit(unit))
                        )
                        .foregroundStyle(.green.opacity(0.9))
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                    }
                }

                // Forecast extension (dashed)
                ForEach(stats.forecastData.prefix(60), id: \.date) { pt in
                    if let date = parseDate(pt.date) {
                        LineMark(
                            x: .value("Date", date),
                            y: .value("Forecast", pt.value.asUnit(unit))
                        )
                        .foregroundStyle(.green.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    }
                }
            }

            // Goal line
            if let goal = appState.settings.goalWeight {
                let gv = goal.asUnit(unit)
                RuleMark(y: .value("Goal", gv))
                    .foregroundStyle(.red.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                        Text("Goal")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.red.opacity(0.8))
                            .padding(.horizontal, 4)
                            .background(.background.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(preset: .aligned) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel()
                    .foregroundStyle(Color.secondary.opacity(0.8))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel()
                    .foregroundStyle(Color.secondary.opacity(0.8))
            }
        }
    }

    private func regressionPoints(slope: Double) -> [(date: String, value: Double)] {
        guard let first = entries.first else { return [] }
        let days = StatisticsService.daysBetween(first.date, entries.last?.date ?? first.date)
        guard days > 0, let base = first.parsedDate else { return [] }
        let step = max(1, days / 60)
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.locale = Locale(identifier: "en_US_POSIX")
        return stride(from: 0, through: days, by: step).compactMap { d in
            guard let date = Calendar.current.date(byAdding: .day, value: d, to: base) else { return nil }
            return (fmt.string(from: date), first.weightLbs + slope * Double(d))
        }
    }

    private func parseDate(_ s: String) -> Date? {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.date(from: s)
    }
}

// AreaChartView and MovingAverageChartView live here since they're peers of ScatterChartView

struct AreaChartView: View {
    @EnvironmentObject var appState: AppState
    var entries: [WeightEntry]

    private var unit: WeightUnit { appState.settings.weightUnit }
    private var accent: Color { appState.effectiveAccentColor }

    private var yDomain: ClosedRange<Double> {
        let weights = entries.map { $0.displayWeight(unit: unit) }
        guard let lo = weights.min(), let hi = weights.max(), lo < hi else { return 0...200 }
        let pad = (hi - lo) * 0.12
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        Chart {
            ForEach(entries) { entry in
                if let date = entry.parsedDate {
                    let w = entry.displayWeight(unit: unit)
                    AreaMark(x: .value("Date", date), y: .value("Weight", w))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accent.opacity(0.45), accent.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Date", date), y: .value("Weight", w))
                        .foregroundStyle(accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)
                }
            }
            if let goal = appState.settings.goalWeight {
                let gv = goal.asUnit(unit)
                RuleMark(y: .value("Goal", gv))
                    .foregroundStyle(.red.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(preset: .aligned) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel().foregroundStyle(Color.secondary.opacity(0.8))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel().foregroundStyle(Color.secondary.opacity(0.8))
            }
        }
    }
}

struct MovingAverageChartView: View {
    @EnvironmentObject var appState: AppState
    var entries: [WeightEntry]

    private var unit: WeightUnit { appState.settings.weightUnit }
    private var accent: Color { appState.effectiveAccentColor }

    private var ma7: [(date: String, value: Double)] {
        StatisticsService.movingAverage(sorted: entries.sorted { $0.date < $1.date }, window: 7)
    }
    private var ma30: [(date: String, value: Double)] {
        StatisticsService.movingAverage(sorted: entries.sorted { $0.date < $1.date }, window: 30)
    }

    private var yDomain: ClosedRange<Double> {
        let weights = entries.map { $0.displayWeight(unit: unit) }
        guard let lo = weights.min(), let hi = weights.max(), lo < hi else { return 0...200 }
        let pad = (hi - lo) * 0.12
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        Chart {
            // Raw points, muted
            ForEach(entries) { entry in
                if let date = entry.parsedDate {
                    PointMark(
                        x: .value("Date", date),
                        y: .value("Weight", entry.displayWeight(unit: unit))
                    )
                    .foregroundStyle(accent.opacity(0.2))
                    .symbolSize(12)
                }
            }
            // 7-day MA
            ForEach(ma7, id: \.date) { pt in
                if let date = parseDate(pt.date) {
                    LineMark(x: .value("Date", date), y: .value("7-day", pt.value.asUnit(unit)))
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)
                }
            }
            // 30-day MA
            ForEach(ma30, id: \.date) { pt in
                if let date = parseDate(pt.date) {
                    LineMark(x: .value("Date", date), y: .value("30-day", pt.value.asUnit(unit)))
                        .foregroundStyle(.purple)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)
                }
            }
        }
        .chartForegroundStyleScale([
            "7-day": Color.orange,
            "30-day": Color.purple,
            "Weight": accent.opacity(0.2)
        ])
        .chartLegend(position: .topLeading, spacing: 8)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(preset: .aligned) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel().foregroundStyle(Color.secondary.opacity(0.8))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel().foregroundStyle(Color.secondary.opacity(0.8))
            }
        }
    }

    private func parseDate(_ s: String) -> Date? {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.date(from: s)
    }
}
