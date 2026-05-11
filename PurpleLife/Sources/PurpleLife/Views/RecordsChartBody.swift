import Charts
import SwiftUI

/// "Charts" view kind for `RecordsScreen`. Renders the type's primary
/// numeric field as a time-series line chart, with a time-range
/// picker (7D / 30D / 90D / 1Y / All).
///
/// **Predicate** (set by `RecordsScreen.viewKindsForCurrentType`):
/// the type must have at least one date-bearing field AND its
/// `primaryFieldKey` must point at a `.number` field. The Weight type
/// satisfies both (date + pounds); types like Person don't and the
/// Charts tab won't appear in the picker.
///
/// **Same-day dedup**: PurpleLife has no unique-per-day constraint
/// (unlike WeightTracker's date-keyed schema). When the user has more
/// than one record on the same calendar day, the chart keeps the
/// most-recently-updated record and drops the rest. Documented as
/// last-write-wins per day in HANDOFF.
struct RecordsChartBody: View {
    @EnvironmentObject private var appState: AppState
    let type: ObjectType
    let rows: [ObjectRecord]

    @State private var range: TimeRange = .d30
    // Overlay toggles. All three are applicable only to the Weight
    // type (regression + 7-day MA need StatisticsService; Goal line
    // needs AppSettings.goalWeightPounds). Hidden in the toolbar for
    // other types.
    @State private var showTrendLine: Bool = false
    @State private var show7dAverage: Bool = false
    @State private var showGoalLine: Bool = true

    enum TimeRange: String, CaseIterable, Identifiable {
        case d7   = "7D"
        case d30  = "30D"
        case d90  = "90D"
        case y1   = "1Y"
        case all  = "All"

        var id: String { rawValue }

        /// Days back from today to include. `nil` means "all data."
        var days: Int? {
            switch self {
            case .d7:  return 7
            case .d30: return 30
            case .d90: return 90
            case .y1:  return 365
            case .all: return nil
            }
        }
    }

    var body: some View {
        let valueKey = type.primaryFieldKey ?? ""
        let dateKey = dateFieldKey(in: type) ?? ""
        let allPoints = RecordsChartBody.extractPoints(
            rows: rows,
            dateKey: dateKey,
            valueKey: valueKey
        )
        let visiblePoints = filtered(allPoints)
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Divider()
            if visiblePoints.isEmpty {
                emptyForRange
            } else {
                chart(points: visiblePoints)
                    .padding(20)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 14) {
            Picker("Range", selection: $range) {
                ForEach(TimeRange.allCases) { r in
                    Text(r.rawValue).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)
            Spacer()
            if type.id == "Weight" {
                Toggle("Trend", isOn: $showTrendLine)
                    .toggleStyle(.checkbox)
                Toggle("7d avg", isOn: $show7dAverage)
                    .toggleStyle(.checkbox)
                Toggle("Goal", isOn: $showGoalLine)
                    .toggleStyle(.checkbox)
                    .disabled(appState.settings.goalWeightPounds == nil)
                    .help(appState.settings.goalWeightPounds == nil
                          ? "Set Goal weight in Settings → Weight"
                          : "Show Goal line at \(appState.settings.goalWeightPounds!) lb")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var emptyForRange: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No data in this range")
                .font(.headline).foregroundStyle(.secondary)
            Text("Try a wider range, or add records.")
                .font(.subheadline).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chart

    private func chart(points: [(date: Date, value: Double)]) -> some View {
        let tone = Color(hex: type.colorHex) ?? .accentColor
        // Collect all the values that participate in the y-axis so a
        // goal line outside the data range still fits in the chart's
        // visible domain.
        var yValues = points.map(\.value)
        let overlays = computeOverlays(points: points)
        if let trend = overlays.trend { yValues.append(contentsOf: trend.map(\.value)) }
        if let goal = overlays.goal { yValues.append(goal) }
        let (yMin, yMax) = paddedYDomain(values: yValues)
        let primaryName = type.field(forKey: type.primaryFieldKey ?? "")?.name ?? "Value"
        return Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                AreaMark(
                    x: .value("Date", p.date),
                    y: .value(primaryName, p.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [tone.opacity(0.30), tone.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("Date", p.date),
                    y: .value(primaryName, p.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tone)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            // 7-day moving average overlay — secondary line, no area.
            if let ma = overlays.movingAverage {
                ForEach(Array(ma.enumerated()), id: \.offset) { _, p in
                    LineMark(
                        x: .value("Date", p.date),
                        y: .value("7-day avg", p.value),
                        series: .value("Series", "ma7")
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [4, 3]))
                }
            }
            // Trend (linear regression) — straight line from first to
            // last predicted value.
            if let trend = overlays.trend, trend.count >= 2 {
                ForEach(Array(trend.enumerated()), id: \.offset) { _, p in
                    LineMark(
                        x: .value("Date", p.date),
                        y: .value("Trend", p.value),
                        series: .value("Series", "trend")
                    )
                    .foregroundStyle(.purple)
                    .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [2, 4]))
                }
            }
            // Goal line — horizontal RuleMark at the goal weight.
            if let goal = overlays.goal {
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
                    .annotation(position: .topTrailing, alignment: .trailing) {
                        Text("Goal · \(String(format: "%.0f", goal))")
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Capsule())
                    }
            }
        }
        .chartYScale(domain: yMin...yMax)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Overlays

    private struct Overlays {
        var trend: [(date: Date, value: Double)]?
        var movingAverage: [(date: Date, value: Double)]?
        var goal: Double?
    }

    private func computeOverlays(points: [(date: Date, value: Double)]) -> Overlays {
        guard type.id == "Weight", points.count >= 2 else { return Overlays() }
        var out = Overlays()
        let (slope, _) = StatisticsService.linearRegression(sorted: points)
        if showTrendLine, let slope, let first = points.first, let last = points.last {
            // Two endpoints define the regression line within the
            // visible date range. Intercept derived from the first
            // point's residual so the line passes through the data
            // cloud, not out of bounds.
            let intercept = first.value - slope * 0
            let lastDays = StatisticsService.daysBetween(first.date, last.date)
            out.trend = [
                (date: first.date, value: intercept),
                (date: last.date, value: intercept + slope * Double(lastDays)),
            ]
        }
        if show7dAverage {
            let ma = StatisticsService.movingAverage(sorted: points, window: 7)
            if !ma.isEmpty { out.movingAverage = ma }
        }
        if showGoalLine, let g = appState.settings.goalWeightPounds {
            out.goal = g
        }
        return out
    }

    // MARK: - Range filter

    private func filtered(_ points: [(date: Date, value: Double)]) -> [(date: Date, value: Double)] {
        guard let days = range.days else { return points }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return points.filter { $0.date >= cutoff }
    }

    private func paddedYDomain(values: [Double]) -> (Double, Double) {
        guard let mn = values.min(), let mx = values.max() else { return (0, 1) }
        let range = mx - mn
        // 12% padding above + below; clamp to a minimum so flat data
        // (all values equal) still renders a meaningful gap rather
        // than a degenerate domain.
        let pad = max(range * 0.12, max(abs(mx) * 0.05, 0.5))
        return (mn - pad, mx + pad)
    }

    // MARK: - Schema helpers

    /// First date-bearing field key on the type, preferring the
    /// `calendarDateKey` setting if present (so types that disagree
    /// about which date to chart can hint via that field).
    private func dateFieldKey(in type: ObjectType) -> String? {
        if let k = type.calendarDateKey, type.field(forKey: k)?.kind.canDateForCalendar == true {
            return k
        }
        return type.fields.first(where: { $0.kind.canDateForCalendar })?.key
    }

    // MARK: - Pure extraction (testable, nonisolated)

    /// Walk `rows`, pull a `(date, value)` pair from each by reading
    /// `dateKey` + `valueKey`, dedupe by calendar day (keeping the
    /// most-recent `updatedAt` per day), and return sorted ascending.
    /// Static + nonisolated so unit tests can call without spinning a
    /// MainActor host.
    nonisolated static func extractPoints(
        rows: [ObjectRecord],
        dateKey: String,
        valueKey: String
    ) -> [(date: Date, value: Double)] {
        guard !dateKey.isEmpty, !valueKey.isEmpty else { return [] }
        struct Raw { let date: Date; let value: Double; let updatedAt: String }
        let raws: [Raw] = rows.compactMap { r in
            let f = r.fields()
            guard let d = parseISODate(f[dateKey]),
                  let v = numericValue(f[valueKey]) else { return nil }
            return Raw(date: d, value: v, updatedAt: r.updatedAt)
        }
        let cal = Calendar.current
        let grouped = Dictionary(grouping: raws) { cal.startOfDay(for: $0.date) }
        return grouped.compactMap { (day, group) -> (date: Date, value: Double)? in
            guard let pick = group.max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
            return (day, pick.value)
        }
        .sorted { $0.date < $1.date }
    }

    nonisolated private static func parseISODate(_ raw: Any?) -> Date? {
        guard let s = raw as? String else { return nil }
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        // Some records may have date-only ("yyyy-MM-dd") rather than
        // full ISO-8601 (the Weight type's Date field is .date, no
        // time component, so it round-trips through DatePicker as
        // "yyyy-MM-dd" or full ISO depending on caller).
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    nonisolated private static func numericValue(_ raw: Any?) -> Double? {
        guard let raw, !(raw is NSNull) else { return nil }
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        if let s = raw as? String { return Double(s) }
        return nil
    }
}
