import XCTest
@testable import PurpleLife

/// Free-form text parser coverage. Each date format gets a hit; weight
/// extraction respects plausibility bounds (50-700 lb); same-day
/// duplicates within the input collapse to the first occurrence;
/// pre-existing duplicates are flagged and pre-deselected.
final class SmartWeightImporterTests: XCTestCase {

    private func parse(_ text: String, existing: Set<Date> = []) -> [SmartWeightImporter.ParsedWeightEntry] {
        SmartWeightImporter.parse(text: text, existingDays: existing)
    }

    private func dayString(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    // MARK: - Date format coverage

    func testParsesISO8601() {
        let out = parse("2024-01-15  185.5")
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(dayString(out[0].date), "2024-01-15")
        XCTAssertEqual(out[0].pounds, 185.5, accuracy: 0.001)
    }

    func testParsesSlashDate() {
        let out = parse("01/15/2024 185.5")
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(dayString(out[0].date), "2024-01-15")
    }

    func testParsesShortSlashDate() {
        let out = parse("1/5/2024 180")
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(dayString(out[0].date), "2024-01-05")
    }

    func testParsesDashDate() {
        let out = parse("01-15-2024 185.5")
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(dayString(out[0].date), "2024-01-15")
    }

    func testParsesAbbreviatedMonthName() {
        let out = parse("Jan 15 2024 185.5")
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(dayString(out[0].date), "2024-01-15")
    }

    func testParsesFullMonthName() {
        let out = parse("January 15, 2024  185.5 lbs")
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(dayString(out[0].date), "2024-01-15")
        XCTAssertEqual(out[0].pounds, 185.5, accuracy: 0.001)
    }

    func testParsesPlainEnglishSentence() {
        let out = parse("On 3/5/2024 I weighed 182 pounds")
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(dayString(out[0].date), "2024-03-05")
        XCTAssertEqual(out[0].pounds, 182, accuracy: 0.001)
    }

    // MARK: - Plausibility bounds

    func testRejectsImplausibleWeights() {
        // 12 lb (under 50) and 1500 lb (over 700) — neither is human weight
        let out1 = parse("2024-01-15 12")
        XCTAssertTrue(out1.isEmpty, "12 lb should be rejected as below plausibility floor")

        // 1500 has 4 digits and won't match the (?<!\d)(\d{2,3}...)(?!\d)
        // regex; effectively "no plausible weight on the line"
        let out2 = parse("2024-01-15 1500")
        XCTAssertTrue(out2.isEmpty)
    }

    func testWeightExtractionAvoidsYearDigits() {
        // Year 2024 contains a 3-digit run "024" / "024" at the end.
        // The lookarounds in the weight regex should prevent matching
        // those as a weight.
        let out = parse("2024-01-15 185.5")
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].pounds, 185.5, accuracy: 0.001,
                       "year digits must not be matched as weight")
    }

    // MARK: - Dedup behavior

    func testCollapsesSameDayDuplicatesWithinInput() {
        // Two lines for 2024-01-15 — first wins, second dropped
        let text = """
        2024-01-15 185.5
        2024-01-15 184.0
        """
        let out = parse(text)
        XCTAssertEqual(out.count, 1, "same-day duplicates within input should collapse")
        XCTAssertEqual(out.first?.pounds, 185.5)
    }

    func testFlagsAndPreDeselectsExistingDays() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let existing = Set([f.date(from: "2024-01-15")!])
        let out = parse("2024-01-15 185.5\n2024-01-16 184.0", existing: existing)
        XCTAssertEqual(out.count, 2)
        XCTAssertTrue(out[0].isDuplicate, "matching existing day must be flagged")
        XCTAssertFalse(out[0].isSelected, "duplicates must be pre-deselected")
        XCTAssertFalse(out[1].isDuplicate)
        XCTAssertTrue(out[1].isSelected)
    }

    // MARK: - Empty / unmatched input

    func testEmptyInputReturnsEmpty() {
        XCTAssertTrue(parse("").isEmpty)
        XCTAssertTrue(parse("   \n\n   ").isEmpty)
    }

    func testLinesWithoutDateOrWeightAreSkipped() {
        let out = parse("just a sentence with no useful data\nanother garbage line")
        XCTAssertTrue(out.isEmpty)
    }
}
