import XCTest
@testable import PurpleDiary

final class StatsTests: XCTestCase {

    private let cal = Calendar(identifier: .gregorian)

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func entry(on date: Date, mood: Int = 0, words: Int = 0) -> Entry {
        var e = Entry.newDraft(date: date)
        e.moodRating = mood
        e.wordCount = words
        return e
    }

    func testEmptyJournal() {
        let s = StatsService.compute(entries: [], calendar: cal)
        XCTAssertEqual(s.totalEntries, 0)
        XCTAssertEqual(s.totalWords, 0)
        XCTAssertEqual(s.daysJournaled, 0)
        XCTAssertNil(s.averageMood)
        XCTAssertEqual(s.currentStreakDays, 0)
        XCTAssertEqual(s.longestStreakDays, 0)
        XCTAssertTrue(s.entriesPerMonth.isEmpty)
    }

    func testTotalsAndAverageMoodExcludesUnset() {
        let entries = [
            entry(on: day(2026, 3, 1), mood: 4, words: 100),
            entry(on: day(2026, 3, 2), mood: 0, words: 50),   // unset mood — excluded from avg
            entry(on: day(2026, 3, 2), mood: 2, words: 25),   // second entry same day
        ]
        let s = StatsService.compute(entries: entries, calendar: cal, now: day(2026, 3, 3))
        XCTAssertEqual(s.totalEntries, 3)
        XCTAssertEqual(s.totalWords, 175)
        XCTAssertEqual(s.daysJournaled, 2, "two distinct calendar days")
        XCTAssertEqual(s.averageMood, 3.0, "average of 4 and 2, ignoring the unset one")
    }

    func testEntriesPerMonthBuckets() {
        let entries = [
            entry(on: day(2026, 2, 10), words: 10),
            entry(on: day(2026, 2, 20), words: 20),
            entry(on: day(2026, 3, 1), words: 5),
        ]
        let s = StatsService.compute(entries: entries, calendar: cal, now: day(2026, 3, 2))
        XCTAssertEqual(s.entriesPerMonth.count, 2)
        XCTAssertEqual(s.entriesPerMonth[0].count, 2)   // Feb, chronological first
        XCTAssertEqual(s.entriesPerMonth[0].words, 30)
        XCTAssertEqual(s.entriesPerMonth[1].count, 1)   // Mar
        XCTAssertEqual(s.entriesPerMonth[1].words, 5)
    }

    func testTagCountsDescending() {
        let e1 = entry(on: day(2026, 3, 1))
        let e2 = entry(on: day(2026, 3, 2))
        let work = Tag(rowId: 1, name: "work", colorHex: "#3FA9F5")
        let personal = Tag(rowId: 2, name: "personal", colorHex: "#7C5CFF")
        let tagsByEntry = [e1.id: [work, personal], e2.id: [work]]
        let s = StatsService.compute(entries: [e1, e2], tagsByEntry: tagsByEntry, calendar: cal, now: day(2026, 3, 3))
        XCTAssertEqual(s.tagCounts.first?.name, "work")
        XCTAssertEqual(s.tagCounts.first?.count, 2)
        XCTAssertEqual(s.tagCounts.last?.name, "personal")
    }

    // MARK: - Streaks

    func testCurrentStreakCountsBackFromToday() {
        let now = day(2026, 3, 10)
        let days: Set<Date> = [
            cal.startOfDay(for: day(2026, 3, 10)),
            cal.startOfDay(for: day(2026, 3, 9)),
            cal.startOfDay(for: day(2026, 3, 8)),
        ]
        let r = StatsService.streaks(days: days, calendar: cal, now: now)
        XCTAssertEqual(r.current, 3)
        XCTAssertEqual(r.longest, 3)
    }

    func testCurrentStreakFallsBackToYesterday() {
        let now = day(2026, 3, 10)   // no entry today
        let days: Set<Date> = [
            cal.startOfDay(for: day(2026, 3, 9)),
            cal.startOfDay(for: day(2026, 3, 8)),
        ]
        let r = StatsService.streaks(days: days, calendar: cal, now: now)
        XCTAssertEqual(r.current, 2, "streak ending yesterday still counts")
    }

    func testCurrentStreakZeroWhenStale() {
        let now = day(2026, 3, 10)
        let days: Set<Date> = [
            cal.startOfDay(for: day(2026, 3, 1)),
            cal.startOfDay(for: day(2026, 2, 28)),
        ]
        let r = StatsService.streaks(days: days, calendar: cal, now: now)
        XCTAssertEqual(r.current, 0, "no entry today or yesterday → current streak 0")
        XCTAssertEqual(r.longest, 2)
    }

    func testLongestStreakAcrossGaps() {
        let now = day(2026, 3, 20)
        let days: Set<Date> = [
            // a 4-day run
            cal.startOfDay(for: day(2026, 3, 1)),
            cal.startOfDay(for: day(2026, 3, 2)),
            cal.startOfDay(for: day(2026, 3, 3)),
            cal.startOfDay(for: day(2026, 3, 4)),
            // gap, then a 2-day run
            cal.startOfDay(for: day(2026, 3, 10)),
            cal.startOfDay(for: day(2026, 3, 11)),
        ]
        let r = StatsService.streaks(days: days, calendar: cal, now: now)
        XCTAssertEqual(r.longest, 4)
        XCTAssertEqual(r.current, 0)
    }
}
