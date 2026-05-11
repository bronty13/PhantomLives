import SwiftUI

/// Sheet showing the WeightStats bundle that StatisticsService
/// produces. Four sections: Overview, Trend, BMI (only when
/// `heightInches` is set), Forecast.
///
/// Triggered from `RecordsScreen`'s toolbar when viewing the Weight
/// type. Read-only — all the numbers come from records + the four
/// AppSettings profile values; the user edits those in Settings →
/// Weight.
struct WeightStatisticsPanel: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let typeId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundStyle(Color(hex: "#E8A93B") ?? .accentColor)
                Text("Weight statistics").font(.title2).bold()
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider()
            ScrollView {
                if let stats = computeStats() {
                    VStack(alignment: .leading, spacing: 18) {
                        overview(stats)
                        Divider()
                        trend(stats)
                        if stats.bmi != nil {
                            Divider()
                            bmi(stats)
                        }
                        Divider()
                        forecast(stats)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    notEnoughData
                }
            }
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    // MARK: - Sections

    private func overview(_ s: WeightStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Overview")
            statRow("Starting", value: pounds(s.startWeight))
            statRow("Current", value: pounds(s.currentWeight))
            if let goal = s.goalWeight {
                statRow("Goal", value: pounds(goal))
            }
            statRow(
                "Total change",
                value: pounds(s.totalChange, signed: true),
                color: changeColor(s.totalChange)
            )
            if let pct = s.percentToGoal {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Progress to goal")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f%%", pct))
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                    }
                    ProgressView(value: pct / 100)
                        .tint(Theme.accent)
                }
                .padding(.top, 4)
            }
        }
    }

    private func trend(_ s: WeightStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Trend analysis")
            if let weekly = s.averageWeeklyChange {
                statRow(
                    "Weekly rate (last 4 wks)",
                    value: pounds(weekly, signed: true) + " / wk",
                    color: changeColor(weekly)
                )
            }
            if let slope = s.regressionSlope {
                statRow(
                    "Regression slope",
                    value: String(format: "%+.3f lb / day", slope),
                    color: changeColor(slope)
                )
            }
            if let r2 = s.regressionR2 {
                statRow(
                    "R² consistency",
                    value: String(format: "%.2f", r2)
                )
            }
            if let best = s.bestWeek {
                statRow(
                    "Best week",
                    value: String(format: "−%.2f lb (week of %@)", best.loss, dateLabel(best.start))
                )
            }
            if let worst = s.worstWeek {
                statRow(
                    "Worst week",
                    value: String(format: "%+.2f lb (week of %@)", -worst.gain, dateLabel(worst.start))
                )
            }
        }
    }

    private func bmi(_ s: WeightStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("BMI")
            if let bmi = s.bmi {
                statRow("Current", value: String(format: "%.1f · %@", bmi, bmiCategory(bmi)))
            }
            if let starting = s.startingBMI {
                statRow("Starting", value: String(format: "%.1f", starting))
            }
            if let goalBMI = s.goalBMI {
                statRow("Goal", value: String(format: "%.1f · %@", goalBMI, bmiCategory(goalBMI)))
            }
        }
    }

    private func forecast(_ s: WeightStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Forecast")
            if let slope = s.regressionSlope, slope < 0, let days = s.daysToGoal {
                statRow(
                    "Days to goal",
                    value: days == 0 ? "already there" : "\(days)",
                    color: .green
                )
            } else if s.goalWeight != nil {
                Text("Need a downward trend across ≥3 entries to estimate days to goal.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            // Projection samples at common horizons.
            ForEach([7, 14, 30, 60, 90], id: \.self) { d in
                if let entry = s.forecastData.first(where: { calendarDayOffset($0.date) == d }) {
                    statRow("In \(d) days", value: pounds(entry.value))
                }
            }
        }
    }

    // MARK: - Bits

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
    }

    private func statRow(_ label: String, value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    private var notEnoughData: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Not enough data yet")
                .font(.headline).foregroundStyle(.secondary)
            Text("Statistics need at least 2 records.")
                .font(.subheadline).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Compute + format

    private func computeStats() -> WeightStats? {
        let rows = (try? appState.database.fetchObjects(typeId: typeId)) ?? []
        return StatisticsService.computeForWeightRecords(rows, settings: appState.settings)
    }

    private func pounds(_ value: Double, signed: Bool = false) -> String {
        if signed {
            return String(format: "%@%.1f lb", value >= 0 ? "+" : "−", abs(value))
        }
        return String(format: "%.1f lb", value)
    }

    /// Loss = green (typical user goal); gain = orange. Same scheme as
    /// the rail card delta — no semantic claim, just sign-readable.
    private func changeColor(_ value: Double) -> Color {
        value < 0 ? .green : (value > 0 ? .orange : .secondary)
    }

    private func bmiCategory(_ bmi: Double) -> String {
        switch bmi {
        case ..<18.5:    return "underweight"
        case 18.5..<25:  return "healthy"
        case 25..<30:    return "overweight"
        default:         return "obese"
        }
    }

    private func dateLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    private func calendarDayOffset(_ d: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Date(), to: d).day ?? 0
    }
}
