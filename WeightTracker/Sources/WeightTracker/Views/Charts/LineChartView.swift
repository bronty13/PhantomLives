import SwiftUI
import Charts

struct LineChartView: View {
    @EnvironmentObject var appState: AppState
    var entries: [WeightEntry]
    var showTrend: Bool
    var showGoal: Bool
    var showMovingAvg: Bool

    private var unit: WeightUnit { appState.settings.weightUnit }
    private var accent: Color { appState.effectiveAccentColor }
    private var palette: [Color] { appState.currentTheme.chartPalette }

    private var yDomain: ClosedRange<Double> {
        let weights = entries.map { $0.displayWeight(unit: unit) }
        guard let lo = weights.min(), let hi = weights.max(), lo < hi else { return 0...200 }
        let pad = (hi - lo) * 0.12
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        Chart {
            // Gradient fill under the line
            ForEach(entries) { entry in
                if let date = entry.parsedDate {
                    AreaMark(
                        x: .value("Date", date),
                        y: .value("Weight", entry.displayWeight(unit: unit))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accent.opacity(0.25), accent.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }

            // Main data line
            ForEach(entries) { entry in
                if let date = entry.parsedDate {
                    LineMark(
                        x: .value("Date", date),
                        y: .value("Weight", entry.displayWeight(unit: unit))
                    )
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                    .symbol {
                        Circle()
                            .fill(accent)
                            .frame(width: entries.count > 60 ? 0 : 6)
                            .overlay(Circle().stroke(.background, lineWidth: 1.5).frame(width: entries.count > 60 ? 0 : 6))
                    }
                }
            }

            // 7-day moving average
            if showMovingAvg {
                ForEach(appState.stats?.movingAverage7 ?? [], id: \.date) { pt in
                    if let date = parseDate(pt.date) {
                        LineMark(
                            x: .value("Date", date),
                            y: .value("7-day", pt.value.asUnit(unit))
                        )
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    }
                }
            }

            // Regression trend line
            if showTrend, let stats = appState.stats, let slope = stats.regressionSlope {
                ForEach(trendPoints(slope: slope, entries: entries), id: \.date) { pt in
                    if let date = parseDate(pt.date) {
                        LineMark(
                            x: .value("Date", date),
                            y: .value("Trend", pt.value.asUnit(unit))
                        )
                        .foregroundStyle(.green.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    }
                }
            }

            // Goal rule
            if showGoal, let goal = appState.settings.goalWeight {
                let gv = goal.asUnit(unit)
                RuleMark(y: .value("Goal", gv))
                    .foregroundStyle(.red.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                        Text("Goal \(String(format: "%.0f", gv))")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.red.opacity(0.8))
                            .padding(.horizontal, 4)
                            .background(.background.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
            }

            // Min / max annotations
            if let minEntry = entries.min(by: { $0.displayWeight(unit: unit) < $1.displayWeight(unit: unit) }),
               let minDate = minEntry.parsedDate {
                PointMark(
                    x: .value("Date", minDate),
                    y: .value("Min", minEntry.displayWeight(unit: unit))
                )
                .symbolSize(0)
                .annotation(position: .bottom, alignment: .center, spacing: 4) {
                    Text(String(format: "%.0f", minEntry.displayWeight(unit: unit)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green.opacity(0.9))
                }
            }
            if let maxEntry = entries.max(by: { $0.displayWeight(unit: unit) < $1.displayWeight(unit: unit) }),
               let maxDate = maxEntry.parsedDate {
                PointMark(
                    x: .value("Date", maxDate),
                    y: .value("Max", maxEntry.displayWeight(unit: unit))
                )
                .symbolSize(0)
                .annotation(position: .top, alignment: .center, spacing: 4) {
                    Text(String(format: "%.0f", maxEntry.displayWeight(unit: unit)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red.opacity(0.9))
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .stride(by: xStride)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel(format: xFormat)
                    .foregroundStyle(Color.secondary.opacity(0.8))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 6)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel()
                    .foregroundStyle(Color.secondary.opacity(0.8))
            }
        }
    }

    private var xStride: Calendar.Component {
        switch entries.count {
        case 0...14: return .day
        case 15...60: return .weekOfYear
        default: return .month
        }
    }

    private var xFormat: Date.FormatStyle {
        switch entries.count {
        case 0...60: return .dateTime.month(.abbreviated).day()
        default: return .dateTime.month(.abbreviated).year(.twoDigits)
        }
    }

    private func trendPoints(slope: Double, entries: [WeightEntry]) -> [(date: String, value: Double)] {
        guard let first = entries.first, let last = entries.last else { return [] }
        let days = StatisticsService.daysBetween(first.date, last.date)
        guard days > 0, let base = first.parsedDate else { return [] }
        let startVal = first.weightLbs
        let step = max(1, days / 60)
        return stride(from: 0, through: days, by: step).compactMap { d in
            guard let date = Calendar.current.date(byAdding: .day, value: d, to: base) else { return nil }
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.locale = Locale(identifier: "en_US_POSIX")
            return (fmt.string(from: date), startVal + slope * Double(d))
        }
    }

    private func parseDate(_ s: String) -> Date? {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.date(from: s)
    }
}

extension Double {
    func asUnit(_ unit: WeightUnit) -> Double { unit == .lbs ? self : self * 0.453592 }
}
