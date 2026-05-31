import XCTest
@testable import PurpleDiary

/// Phase-4 reflection features: the bundled prompt rotation and the "On This
/// Day" date logic. Both are pure and fully on-device.
final class ReflectionTests: XCTestCase {

    // MARK: - Prompts

    private let sample = [
        Prompt(category: "A", text: "one"),
        Prompt(category: "B", text: "two"),
        Prompt(category: "C", text: "three"),
    ]

    func testDailyIndexWrapsAndIsNonNegative() {
        XCTAssertEqual(PromptService.dailyIndex(dayOrdinal: 0, count: 3), 0)
        XCTAssertEqual(PromptService.dailyIndex(dayOrdinal: 4, count: 3), 1)
        XCTAssertEqual(PromptService.dailyIndex(dayOrdinal: -1, count: 3), 2)  // never crashes / negative
        XCTAssertEqual(PromptService.dailyIndex(dayOrdinal: 99, count: 0), 0)  // empty-library guard
    }

    func testDailyPromptIsStableForTheSameDay() {
        let cal = Calendar(identifier: .gregorian)
        let day = DateComponents(calendar: cal, year: 2026, month: 5, day: 31).date!
        let later = day.addingTimeInterval(60 * 60 * 6)   // same calendar day, hours later
        XCTAssertEqual(PromptService.prompt(for: day, from: sample, calendar: cal),
                       PromptService.prompt(for: later, from: sample, calendar: cal))
    }

    func testConsecutiveDaysAdvanceThePrompt() {
        let cal = Calendar(identifier: .gregorian)
        let d1 = DateComponents(calendar: cal, year: 2026, month: 1, day: 1).date!
        let d2 = cal.date(byAdding: .day, value: 1, to: d1)!
        XCTAssertNotEqual(PromptService.prompt(for: d1, from: sample, calendar: cal),
                          PromptService.prompt(for: d2, from: sample, calendar: cal))
    }

    func testNextCyclesThroughLibrary() {
        XCTAssertEqual(PromptService.next(after: sample[0], in: sample), sample[1])
        XCTAssertEqual(PromptService.next(after: sample[2], in: sample), sample[0]) // wraps
    }

    /// The shipped library must be valid JSON and reasonably stocked. Read from
    /// the source tree (the app bundle isn't present under XCTest).
    func testBundledPromptsFileDecodes() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()       // PurpleDiaryTests
            .deletingLastPathComponent()       // Tests
            .deletingLastPathComponent()       // PurpleDiary
            .appendingPathComponent("Resources/Prompts.json")
        let data = try Data(contentsOf: url)
        let prompts = try JSONDecoder().decode([Prompt].self, from: data)
        XCTAssertGreaterThanOrEqual(prompts.count, 20)
        XCTAssertTrue(prompts.allSatisfy { !$0.text.isEmpty && !$0.category.isEmpty })
    }

    // MARK: - On This Day

    private func entry(_ id: String, _ iso: String) -> Entry {
        var e = Entry.newDraft()
        e.id = id
        e.date = iso
        return e
    }

    func testOnThisDayMatchesMonthDayInPriorYearsNewestFirst() {
        let cal = Calendar(identifier: .gregorian)
        let today = DateComponents(calendar: cal, year: 2026, month: 5, day: 31).date!
        let entries = [
            entry("y2024", "2024-05-31T09:00:00Z"),
            entry("y2023", "2023-05-31T09:00:00Z"),
            entry("today", "2026-05-31T09:00:00Z"),   // excluded (current year)
            entry("other", "2024-05-30T09:00:00Z"),   // excluded (different day)
        ]
        let result = OnThisDayService.entries(from: entries, today: today, calendar: cal)
        XCTAssertEqual(result.map(\.id), ["y2024", "y2023"])   // newest prior year first
    }

    func testYearsAgoAndLabel() {
        let cal = Calendar(identifier: .gregorian)
        let today = DateComponents(calendar: cal, year: 2026, month: 5, day: 31).date!
        let d2024 = DateComponents(calendar: cal, year: 2024, month: 5, day: 31).date!
        XCTAssertEqual(OnThisDayService.yearsAgo(d2024, today: today, calendar: cal), 2)
        XCTAssertEqual(OnThisDayService.label(yearsAgo: 1), "1 year ago")
        XCTAssertEqual(OnThisDayService.label(yearsAgo: 2), "2 years ago")
    }
}
