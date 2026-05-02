import SwiftUI
import Charts

enum TimeRange: String, CaseIterable {
    case week = "7D", month = "30D", quarter = "90D", year = "1Y", all = "All"

    func cutoffDate() -> Date? {
        let cal = Calendar.current
        switch self {
        case .week:    return cal.date(byAdding: .day, value: -7, to: Date())
        case .month:   return cal.date(byAdding: .day, value: -30, to: Date())
        case .quarter: return cal.date(byAdding: .day, value: -90, to: Date())
        case .year:    return cal.date(byAdding: .year, value: -1, to: Date())
        case .all:     return nil
        }
    }
}

struct ChartsView: View {
    @EnvironmentObject var appState: AppState
    // Local state — avoids the settings computed-property reactivity gap
    @State private var chartStyle: ChartStyle = .line
    @State private var timeRange: TimeRange = .all
    @State private var showTrend = true
    @State private var showGoal = true
    @State private var showMovingAvg = false

    var filteredEntries: [WeightEntry] {
        guard let cutoff = timeRange.cutoffDate() else { return appState.entries }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let cutoffStr = fmt.string(from: cutoff)
        return appState.entries.filter { $0.date >= cutoffStr }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if appState.entries.count < 2 {
                    emptyState
                } else {
                    controlsRow
                    chartCard
                    overlayRow
                    statsRow
                }
            }
            .padding(24)
        }
        .onAppear { chartStyle = appState.settings.chartStyle }
    }

    // MARK: - Header

    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Charts")
                .font(.largeTitle.weight(.bold))
            if !appState.entries.isEmpty {
                Text("\(filteredEntries.count) of \(appState.entries.count) entries · \(appState.settings.weightUnit.label)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Controls

    var controlsRow: some View {
        HStack(spacing: 12) {
            // Time range
            Picker("Range", selection: $timeRange.animation(.easeInOut(duration: 0.25))) {
                ForEach(TimeRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

            Spacer()

            // Chart style
            Picker("Style", selection: $chartStyle.animation(.easeInOut(duration: 0.25))) {
                Label("Line",   systemImage: "chart.line.uptrend.xyaxis").tag(ChartStyle.line)
                Label("Bar",    systemImage: "chart.bar.fill").tag(ChartStyle.bar)
                Label("Area",   systemImage: "chart.line.flattrend.xyaxis.circle.fill").tag(ChartStyle.area)
                Label("Scatter",systemImage: "circle.grid.cross").tag(ChartStyle.scatter)
                Label("MA",     systemImage: "waveform.path.ecg").tag(ChartStyle.movingAverage)
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
        }
    }

    // MARK: - Chart card

    var chartCard: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch chartStyle {
                case .line:
                    LineChartView(entries: filteredEntries, showTrend: showTrend,
                                  showGoal: showGoal, showMovingAvg: showMovingAvg)
                case .bar:
                    BarChartView(entries: filteredEntries)
                case .area:
                    AreaChartView(entries: filteredEntries)
                case .scatter:
                    ScatterChartView(entries: filteredEntries)
                case .movingAverage:
                    MovingAverageChartView(entries: filteredEntries)
                }
            }
            .frame(height: 380)
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        .id(chartStyle)
    }

    // MARK: - Toggles

    var overlayRow: some View {
        HStack(spacing: 20) {
            if chartStyle == .line || chartStyle == .area || chartStyle == .scatter {
                legendDot(color: appState.effectiveAccentColor, label: chartStyle.label)
            }
            if chartStyle == .line || chartStyle == .scatter {
                Toggle(isOn: $showTrend) {
                    legendDot(color: .green, label: "Trend")
                }
                .toggleStyle(.checkbox)
                .help("Show regression trend line")
            }
            if chartStyle == .line {
                Toggle(isOn: $showMovingAvg) {
                    legendDot(color: .orange, label: "7-day avg")
                }
                .toggleStyle(.checkbox)
            }
            if (chartStyle == .line || chartStyle == .scatter),
               appState.settings.goalWeight != nil {
                Toggle(isOn: $showGoal) {
                    legendDot(color: .red.opacity(0.7), label: "Goal")
                }
                .toggleStyle(.checkbox)
            }
            Spacer()
            if let r2 = appState.stats?.regressionR2 {
                Text("R² \(String(format: "%.2f", r2))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("Trend consistency: 1.0 = perfect linear trend")
            }
        }
        .font(.caption)
    }

    func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
        }
    }

    // MARK: - Stats strip

    var statsRow: some View {
        let unit = appState.settings.weightUnit
        let entries = filteredEntries
        guard entries.count >= 2 else { return AnyView(EmptyView()) }
        let first = entries.first!.displayWeight(unit: unit)
        let last = entries.last!.displayWeight(unit: unit)
        let change = last - first
        let days = StatisticsService.daysBetween(entries.first!.date, entries.last!.date)
        let minW = entries.map { $0.displayWeight(unit: unit) }.min()!
        let maxW = entries.map { $0.displayWeight(unit: unit) }.max()!

        return AnyView(HStack(spacing: 0) {
            statPill("Start", ExportService.fmt(first, unit: unit))
            Divider().frame(height: 28)
            statPill("End", ExportService.fmt(last, unit: unit))
            Divider().frame(height: 28)
            statPill("Change", ExportService.fmtChange(change, unit: unit),
                     color: change < 0 ? .green : change > 0 ? .red : .secondary)
            Divider().frame(height: 28)
            statPill("Low", ExportService.fmt(minW, unit: unit))
            Divider().frame(height: 28)
            statPill("High", ExportService.fmt(maxW, unit: unit))
            Divider().frame(height: 28)
            statPill("Days", "\(days)")
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10)))
    }

    func statPill(_ label: String, _ value: String, color: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 44))
                .foregroundStyle(appState.effectiveAccentColor.opacity(0.6))
            Text("Add at least 2 entries to see charts.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
