import SwiftUI
import Charts

/// The Insights dashboard: summary cards plus Swift Charts over the journal —
/// mood over time, entries per month, words per month, and tag usage. All
/// derived from the already-loaded entries via `StatsService`.
struct InsightsView: View {
    @EnvironmentObject private var appState: AppState

    private var stats: StatsService.DiaryStats {
        StatsService.compute(entries: appState.entries, tagsByEntry: appState.tagsByEntry)
    }

    var body: some View {
        Group {
            if appState.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        summaryCards
                        if !stats.moodOverTime.isEmpty { moodChart }
                        entriesPerMonthChart
                        wordsPerMonthChart
                        if !stats.tagCounts.isEmpty { tagChart }
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Insights")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 40)).foregroundStyle(.secondary)
            Text("No insights yet").font(.headline)
            Text("Write a few entries and your stats — mood trends, streaks, and word counts — will show up here.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
        }
    }

    // MARK: - Summary cards

    private var summaryCards: some View {
        let s = stats
        let avgMood = s.averageMood.map { String(format: "%.1f", $0) } ?? "—"
        let cards: [(String, String, String)] = [
            ("Entries", "\(s.totalEntries)", "book.closed"),
            ("Words", "\(s.totalWords)", "text.alignleft"),
            ("Days journaled", "\(s.daysJournaled)", "calendar"),
            ("Avg mood", avgMood, "star.fill"),
            ("Current streak", "\(s.currentStreakDays)d", "flame.fill"),
            ("Longest streak", "\(s.longestStreakDays)d", "trophy.fill"),
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(cards, id: \.0) { card in
                summaryCard(title: card.0, value: card.1, symbol: card.2)
            }
        }
    }

    private func summaryCard(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(appState.effectiveAccentColor)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.title2.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Charts

    private var moodChart: some View {
        chartCard("Mood over time") {
            Chart(stats.moodOverTime) { point in
                LineMark(x: .value("Day", point.day), y: .value("Mood", point.mood))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(appState.effectiveAccentColor)
                PointMark(x: .value("Day", point.day), y: .value("Mood", point.mood))
                    .foregroundStyle(appState.effectiveAccentColor)
            }
            .chartYScale(domain: 1...5)
            .frame(height: 200)
        }
    }

    private var entriesPerMonthChart: some View {
        chartCard("Entries per month") {
            Chart(stats.entriesPerMonth) { bucket in
                BarMark(x: .value("Month", bucket.label),
                        y: .value("Entries", bucket.count))
                    .foregroundStyle(appState.effectiveAccentColor)
            }
            .frame(height: 200)
        }
    }

    private var wordsPerMonthChart: some View {
        chartCard("Words per month") {
            Chart(stats.entriesPerMonth) { bucket in
                BarMark(x: .value("Month", bucket.label),
                        y: .value("Words", bucket.words))
                    .foregroundStyle(appState.effectiveAccentColor.opacity(0.6))
            }
            .frame(height: 200)
        }
    }

    private var tagChart: some View {
        chartCard("Tag usage") {
            Chart(stats.tagCounts) { tag in
                BarMark(x: .value("Uses", tag.count),
                        y: .value("Tag", tag.name))
                    .foregroundStyle(Color(hex: tag.colorHex) ?? appState.effectiveAccentColor)
            }
            .frame(height: max(120, CGFloat(stats.tagCounts.count) * 28))
        }
    }

    private func chartCard<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}
