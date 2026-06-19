import SwiftUI

/// A Diarium-style header for the top of the timeline: the current journal's
/// name + year span beside a little "book", with a strip of at-a-glance stats
/// (Entries · Media · Days · Streak · On This Day). All numbers are derived from
/// the already-loaded `visibleEntries` slice (so they respect the journal /
/// hidden / vault filter) plus the per-entry attachment counts — nothing new is
/// fetched. It scrolls with the entry list.
struct JournalHeaderView: View {
    @EnvironmentObject private var appState: AppState

    private var selectedJournal: Journal? {
        appState.selectedJournalId.flatMap { appState.journalsById[$0] }
    }

    private var title: String { selectedJournal?.name ?? "All Journals" }

    /// The journal's accent: its own color, or the app accent for "All Journals".
    private var bookColor: Color {
        if let hex = selectedJournal?.colorHex, let c = Color(hex: hex) { return c }
        return appState.effectiveAccentColor
    }

    private var stats: StatsService.DiaryStats {
        StatsService.compute(entries: appState.visibleEntries, tagsByEntry: appState.tagsByEntry)
    }

    private var mediaCount: Int {
        appState.visibleEntries.reduce(0) { $0 + (appState.attachmentCountByEntry[$1.id] ?? 0) }
    }

    private var onThisDayCount: Int {
        OnThisDayService.entries(from: appState.visibleEntries).count
    }

    /// "2026", or "2023–2026" across the journal's entries, or the current year
    /// when the journal is empty.
    private var yearSpan: String {
        let cal = Calendar.current
        let years = appState.visibleEntries.map { cal.component(.year, from: $0.dateValue) }
        guard let lo = years.min(), let hi = years.max() else {
            return String(cal.component(.year, from: Date()))
        }
        return lo == hi ? "\(lo)" : "\(lo)–\(hi)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                book
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                    Text(yearSpan)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            statsStrip
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    /// A small closed-book glyph in the journal's color, with a spine highlight.
    private var book: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(bookColor)
            .frame(width: 40, height: 52)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.white.opacity(0.35))
                    .frame(width: 4)
                    .padding(.vertical, 6)
                    .padding(.leading, 6)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 5).stroke(.black.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
    }

    /// The five stats. A horizontal scroll keeps them from crowding in the 320pt
    /// column on narrow setups, while normally fitting without scrolling.
    private var statsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                stat("\(stats.totalEntries)", "Entries")
                stat("\(mediaCount)", "Media")
                stat("\(stats.daysJournaled)", "Days")
                stat("\(stats.currentStreakDays)", "Streak")
                stat("\(onThisDayCount)", "On This Day")
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 58)
        .padding(.trailing, 6)
    }
}
