import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                if appState.entries.isEmpty {
                    emptyState
                } else {
                    statsGrid
                    miniChart
                    recentEntriesSection
                }
            }
            .padding(24)
        }
    }

    var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Welcome back, \(appState.settings.username)")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
            if let stats = appState.stats {
                Text("Tracking since \(appState.entries.first?.date ?? "—") · \(appState.entries.count) entries")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var statsGrid: some View {
        let stats = appState.stats
        let unit = appState.settings.weightUnit
        let accent = appState.effectiveAccentColor

        return LazyVGrid(columns: [
            GridItem(.flexible()), GridItem(.flexible()),
            GridItem(.flexible()), GridItem(.flexible())
        ], spacing: 12) {
            ProgressCardView(
                title: "Current",
                value: stats.map { ExportService.fmt($0.currentWeight, unit: unit) } ?? "—",
                subtitle: "Latest entry",
                icon: "scalemass",
                accent: accent
            )
            ProgressCardView(
                title: "Total Change",
                value: stats.map { ExportService.fmtChange($0.totalChange, unit: unit) } ?? "—",
                subtitle: stats.flatMap { s in s.goalWeight.map { _ in
                    s.percentToGoal.map { String(format: "%.0f%% to goal", $0) } ?? ""
                }},
                icon: "arrow.up.arrow.down",
                accent: stats.map { $0.totalChange < 0 ? Color.green : Color.red } ?? accent
            )
            ProgressCardView(
                title: "Weekly Avg",
                value: stats?.averageWeeklyChange.map { ExportService.fmtChange($0, unit: unit) } ?? "—",
                subtitle: "Rolling 4 weeks",
                icon: "calendar.badge.clock",
                accent: accent
            )
            ProgressCardView(
                title: "Goal",
                value: appState.settings.goalWeight.map { ExportService.fmt($0, unit: unit) } ?? "Not set",
                subtitle: stats?.daysToGoal.map { "\($0) days est." },
                icon: "target",
                accent: accent
            )
        }
    }

    var miniChart: some View {
        let recent = Array(appState.entries.suffix(30))
        let unit = appState.settings.weightUnit

        return VStack(alignment: .leading, spacing: 8) {
            Text("Recent Trend")
                .font(.headline)
            Chart(recent) { entry in
                if let date = entry.parsedDate {
                    LineMark(
                        x: .value("Date", date),
                        y: .value("Weight", entry.displayWeight(unit: unit))
                    )
                    .foregroundStyle(appState.effectiveAccentColor)
                    .interpolationMethod(.catmullRom)
                    AreaMark(
                        x: .value("Date", date),
                        y: .value("Weight", entry.displayWeight(unit: unit))
                    )
                    .foregroundStyle(appState.effectiveAccentColor.opacity(0.15))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    AxisValueLabel()
                        .foregroundStyle(Color.secondary)
                }
            }
            .frame(height: 120)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    var recentEntriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Entries")
                .font(.headline)
            ForEach(appState.entries.suffix(5).reversed()) { entry in
                HStack {
                    Text(entry.date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(ExportService.fmt(entry.displayWeight(unit: appState.settings.weightUnit), unit: appState.settings.weightUnit))
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "scalemass")
                .font(.system(size: 56))
                .foregroundStyle(appState.effectiveAccentColor)
            Text("No entries yet")
                .font(.title2.weight(.semibold))
            Text("Add your first weight entry with ⌘N or use Import to bring in existing data.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
