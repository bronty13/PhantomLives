import SwiftUI
import Charts

struct StatisticsView: View {
    @EnvironmentObject var appState: AppState

    private var unit: WeightUnit { appState.settings.weightUnit }
    private var stats: WeightStats? { appState.stats }
    private var accent: Color { appState.effectiveAccentColor }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Statistics")
                    .font(.largeTitle.weight(.bold))

                if let s = stats {
                    overviewSection(s)
                    trendSection(s)
                    if s.bmi != nil { bmiSection(s) }
                    forecastSection(s)
                } else {
                    Text("Add at least 2 entries to see statistics.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }

    func overviewSection(_ s: WeightStats) -> some View {
        sectionCard("Overview") {
            VStack(spacing: 0) {
                statRow("Starting Weight", ExportService.fmt(s.startWeight, unit: unit))
                Divider().opacity(0.3)
                statRow("Current Weight", ExportService.fmt(s.currentWeight, unit: unit))
                Divider().opacity(0.3)
                if let gw = s.goalWeight {
                    statRow("Goal Weight", ExportService.fmt(gw, unit: unit))
                    Divider().opacity(0.3)
                }
                statRow("Total Change", ExportService.fmtChange(s.totalChange, unit: unit),
                        valueColor: s.totalChange < 0 ? .green : s.totalChange > 0 ? .red : .primary)
                if let pct = s.percentToGoal {
                    Divider().opacity(0.3)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Progress to Goal")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f%%", pct))
                                .fontWeight(.semibold)
                        }
                        ProgressView(value: pct / 100)
                            .tint(accent)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    func trendSection(_ s: WeightStats) -> some View {
        sectionCard("Trend Analysis") {
            VStack(spacing: 0) {
                if let wk = s.averageWeeklyChange {
                    statRow("Avg Weekly Change", ExportService.fmtChange(wk, unit: unit),
                            valueColor: wk < 0 ? .green : .red)
                    Divider().opacity(0.3)
                }
                if let lc = s.lastEntryChange {
                    statRow("Last Entry Change", ExportService.fmtChange(lc, unit: unit),
                            valueColor: lc < 0 ? .green : lc > 0 ? .red : .primary)
                    Divider().opacity(0.3)
                }
                if let slope = s.regressionSlope {
                    let dailyStr = ExportService.fmtChange(slope * 7, unit: unit) + "/week"
                    statRow("Trend Rate", dailyStr, valueColor: slope < 0 ? .green : .red)
                    Divider().opacity(0.3)
                }
                if let r2 = s.regressionR2 {
                    statRow("Trend Consistency (R²)", String(format: "%.3f (%@)", r2, r2 > 0.8 ? "Strong" : r2 > 0.5 ? "Moderate" : "Weak"))
                    Divider().opacity(0.3)
                }
                if let best = s.bestWeek {
                    statRow("Best Week", "\(ExportService.fmtChange(-best.loss, unit: unit)) (week of \(best.start))",
                            valueColor: .green)
                }
            }
        }
    }

    func bmiSection(_ s: WeightStats) -> some View {
        sectionCard("BMI") {
            VStack(spacing: 0) {
                if let bmi = s.bmi {
                    statRow("Current BMI", String(format: "%.1f (%@)", bmi, bmiCategory(bmi)))
                    Divider().opacity(0.3)
                }
                if let sBmi = s.startingBMI {
                    statRow("Starting BMI", String(format: "%.1f", sBmi))
                    Divider().opacity(0.3)
                }
                if let gBmi = s.goalBMI {
                    statRow("Goal BMI", String(format: "%.1f (%@)", gBmi, bmiCategory(gBmi)))
                }
            }
        }
    }

    func forecastSection(_ s: WeightStats) -> some View {
        sectionCard("Forecast") {
            VStack(alignment: .leading, spacing: 12) {
                if let days = s.daysToGoal {
                    statRow("Est. Days to Goal", "\(days) days", valueColor: accent)
                    Divider().opacity(0.3)
                }

                if !s.forecastData.isEmpty {
                    let milestones = [7, 14, 30, 60, 90].compactMap { d -> (days: Int, weight: Double)? in
                        guard d < s.forecastData.count else { return nil }
                        return (d, s.forecastData[d - 1].value)
                    }
                    ForEach(milestones, id: \.days) { m in
                        statRow("In \(m.days) days", ExportService.fmt(m.weight, unit: unit))
                        if m.days != milestones.last?.days { Divider().opacity(0.3) }
                    }
                }
            }
        }
    }

    func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            Divider().opacity(0.4)
            content()
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func statRow(_ label: String, _ value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
                .font(.subheadline)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    func bmiCategory(_ bmi: Double) -> String {
        switch bmi {
        case ..<18.5: return "Underweight"
        case 18.5..<25: return "Normal"
        case 25..<30: return "Overweight"
        default: return "Obese"
        }
    }
}
