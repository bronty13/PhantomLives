import SwiftUI
import Charts

struct BarChartView: View {
    @EnvironmentObject var appState: AppState
    var entries: [WeightEntry]
    @State private var groupBy: GroupBy = .week

    enum GroupBy: String, CaseIterable {
        case week = "Weekly", month = "Monthly"
    }

    private var unit: WeightUnit { appState.settings.weightUnit }
    private var accent: Color { appState.effectiveAccentColor }

    struct Bucket: Identifiable {
        var id: String { label }
        let label: String
        let sortKey: String
        let average: Double
        let min: Double
        let max: Double
        let count: Int
    }

    var buckets: [Bucket] {
        let fmt = DateFormatter(); fmt.locale = Locale(identifier: "en_US_POSIX"); fmt.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current
        var groups: [String: [Double]] = [:]
        var sortKeys: [String: String] = [:]

        for e in entries {
            guard let date = fmt.date(from: e.date) else { continue }
            let key: String
            let sortKey: String
            if groupBy == .week {
                let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
                let yw = comps.yearForWeekOfYear ?? 0
                let wk = comps.weekOfYear ?? 0
                sortKey = String(format: "%04d%02d", yw, wk)
                // Label: Mon of that week
                var wkComps = DateComponents(); wkComps.yearForWeekOfYear = yw; wkComps.weekOfYear = wk; wkComps.weekday = 2
                let weekStart = cal.date(from: wkComps) ?? date
                let lFmt = DateFormatter(); lFmt.dateFormat = "MMM d"
                key = lFmt.string(from: weekStart)
            } else {
                let comps = cal.dateComponents([.year, .month], from: date)
                sortKey = String(format: "%04d%02d", comps.year ?? 0, comps.month ?? 0)
                let lFmt = DateFormatter(); lFmt.dateFormat = "MMM yy"
                key = lFmt.string(from: date)
            }
            groups[key, default: []].append(e.displayWeight(unit: unit))
            sortKeys[key] = sortKey
        }

        return groups.map { key, vals in
            Bucket(
                label: key,
                sortKey: sortKeys[key] ?? key,
                average: vals.reduce(0, +) / Double(vals.count),
                min: vals.min()!,
                max: vals.max()!,
                count: vals.count
            )
        }
        .sorted { $0.sortKey < $1.sortKey }
    }

    private var yDomain: ClosedRange<Double> {
        guard !buckets.isEmpty else { return 0...200 }
        let lo = buckets.map(\.min).min()!
        let hi = buckets.map(\.max).max()!
        let pad = (hi - lo) * 0.15
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Group by", selection: $groupBy) {
                ForEach(GroupBy.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)

            Chart(buckets) { b in
                // Range bar (low–high)
                BarMark(
                    x: .value("Period", b.label),
                    yStart: .value("Min", b.min),
                    yEnd: .value("Max", b.max)
                )
                .foregroundStyle(accent.opacity(0.15))
                .cornerRadius(3)

                // Average bar
                BarMark(
                    x: .value("Period", b.label),
                    yStart: .value("AvgBase", b.average - 0.4),
                    yEnd: .value("Avg", b.average + 0.4)
                )
                .foregroundStyle(accent)
                .cornerRadius(2)

                // Average point
                PointMark(
                    x: .value("Period", b.label),
                    y: .value("Avg", b.average)
                )
                .foregroundStyle(accent)
                .symbolSize(buckets.count < 24 ? 30 : 0)
                .annotation(position: .top, alignment: .center, spacing: 3) {
                    if buckets.count <= 16 {
                        Text(String(format: "%.0f", b.average))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel(orientation: buckets.count > 12 ? .vertical : .horizontal)
                        .font(.caption2)
                        .foregroundStyle(Color.secondary.opacity(0.8))
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.secondary.opacity(0.1))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.secondary.opacity(0.15))
                    AxisValueLabel().foregroundStyle(Color.secondary.opacity(0.8))
                }
            }
        }
    }
}
