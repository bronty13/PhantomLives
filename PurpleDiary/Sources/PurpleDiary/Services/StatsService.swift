import Foundation

/// Pure aggregation of journal statistics for the Insights dashboard. Operates
/// on the already-loaded `[Entry]` slice (instant for a personal journal's row
/// counts). Calendar + reference date are injectable so the streak/bucket logic
/// is deterministically testable.
enum StatsService {

    struct MonthBucket: Identifiable, Equatable {
        let monthStart: Date
        let label: String       // "Mar 2026"
        let count: Int
        let words: Int
        var id: Date { monthStart }
    }

    struct MoodPoint: Identifiable, Equatable {
        let day: Date           // start of day
        let mood: Double        // average mood that day (rated entries only)
        var id: Date { day }
    }

    struct TagCount: Identifiable, Equatable {
        let name: String
        let colorHex: String
        let count: Int
        var id: String { name }
    }

    struct DiaryStats: Equatable {
        var totalEntries: Int = 0
        var totalWords: Int = 0
        var daysJournaled: Int = 0
        var averageMood: Double? = nil       // over rated entries; nil if none rated
        var currentStreakDays: Int = 0
        var longestStreakDays: Int = 0
        var entriesPerMonth: [MonthBucket] = []   // chronological
        var moodOverTime: [MoodPoint] = []        // chronological, rated days only
        var tagCounts: [TagCount] = []            // descending by count
    }

    static func compute(
        entries: [Entry],
        tagsByEntry: [String: [Tag]] = [:],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> DiaryStats {
        var stats = DiaryStats()
        stats.totalEntries = entries.count
        stats.totalWords = entries.reduce(0) { $0 + $1.wordCount }
        guard !entries.isEmpty else { return stats }

        let dated = entries.map { (entry: $0, date: $0.dateValue) }

        // Distinct calendar days journaled.
        let days = Set(dated.map { calendar.startOfDay(for: $0.date) })
        stats.daysJournaled = days.count

        // Average mood over rated entries (mood > 0).
        let rated = dated.filter { $0.entry.moodRating > 0 }
        if !rated.isEmpty {
            stats.averageMood = Double(rated.reduce(0) { $0 + $1.entry.moodRating }) / Double(rated.count)
        }

        // Streaks.
        let (current, longest) = streaks(days: days, calendar: calendar, now: now)
        stats.currentStreakDays = current
        stats.longestStreakDays = longest

        // Entries + words per month.
        var monthCount: [Date: Int] = [:]
        var monthWords: [Date: Int] = [:]
        for d in dated {
            let key = startOfMonth(d.date, calendar: calendar)
            monthCount[key, default: 0] += 1
            monthWords[key, default: 0] += d.entry.wordCount
        }
        let monthFmt = DateFormatter()
        monthFmt.locale = Locale(identifier: "en_US_POSIX")
        monthFmt.dateFormat = "MMM yyyy"
        stats.entriesPerMonth = monthCount.keys.sorted().map { key in
            MonthBucket(monthStart: key,
                        label: monthFmt.string(from: key),
                        count: monthCount[key] ?? 0,
                        words: monthWords[key] ?? 0)
        }

        // Mood over time — daily average of rated entries, chronological.
        var dayMoodSum: [Date: Int] = [:]
        var dayMoodN: [Date: Int] = [:]
        for r in rated {
            let key = calendar.startOfDay(for: r.date)
            dayMoodSum[key, default: 0] += r.entry.moodRating
            dayMoodN[key, default: 0] += 1
        }
        stats.moodOverTime = dayMoodSum.keys.sorted().map { key in
            MoodPoint(day: key, mood: Double(dayMoodSum[key] ?? 0) / Double(dayMoodN[key] ?? 1))
        }

        // Tag usage counts (descending), carrying color for the chart.
        var counts: [String: (color: String, n: Int)] = [:]
        for (_, tags) in tagsByEntry {
            for t in tags {
                let existing = counts[t.name]
                counts[t.name] = (color: t.colorHex, n: (existing?.n ?? 0) + 1)
            }
        }
        stats.tagCounts = counts
            .map { TagCount(name: $0.key, colorHex: $0.value.color, count: $0.value.n) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }

        return stats
    }

    // MARK: - Helpers

    private static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    /// Current and longest consecutive-day streaks. The current streak counts
    /// back from today; if there's no entry today it falls back to a run ending
    /// yesterday (so an evening writer isn't punished mid-day). Returns (0, …)
    /// for an empty set.
    static func streaks(days: Set<Date>, calendar: Calendar = .current, now: Date = Date()) -> (current: Int, longest: Int) {
        guard !days.isEmpty else { return (0, 0) }
        let sorted = days.sorted()

        // Longest run of consecutive days.
        var longest = 1
        var run = 1
        for i in 1..<max(sorted.count, 1) {
            if let prevPlus1 = calendar.date(byAdding: .day, value: 1, to: sorted[i - 1]),
               calendar.isDate(prevPlus1, inSameDayAs: sorted[i]) {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
        }
        if sorted.count == 1 { longest = 1 }

        // Current streak: anchor at today, else yesterday.
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var anchor: Date
        if days.contains(today) {
            anchor = today
        } else if days.contains(yesterday) {
            anchor = yesterday
        } else {
            return (0, longest)
        }
        var current = 0
        var cursor = anchor
        while days.contains(cursor) {
            current += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return (current, longest)
    }
}
