import XCTest
@testable import PurpleDiary

/// Exercises the pure render/encode functions of `ExportService`. The
/// side-effecting `export(...)` dispatcher and the WKWebView PDF path are
/// verified by a real app run (PDF needs a main run loop); these tests cover
/// content, escaping, grouping, and JSON round-trip — the parts most likely to
/// regress silently.
final class ExportServiceTests: XCTestCase {

    private let iso = ISO8601DateFormatter()

    private func entry(_ id: String, date: String, title: String, body: String,
                       mood: Int = 0, words: Int = 0) -> Entry {
        let now = iso.string(from: Date())
        return Entry(id: id, date: date, title: title, bodyMarkdown: body,
                     moodRating: mood, wordCount: words,
                     latitude: nil, longitude: nil, placeName: nil,
                     weatherSummary: nil, temperatureC: nil,
                     createdAt: now, updatedAt: now)
    }

    private func sample() -> [Entry] {
        [
            entry("E1", date: "2026-01-15T09:00:00Z", title: "New year start",
                  body: "Feeling **great** today.", mood: 5, words: 3),
            entry("E2", date: "2026-02-03T18:30:00Z", title: "Rainy day",
                  body: "A quieter one.", mood: 2, words: 3),
            entry("E3", date: "2025-12-20T12:00:00Z", title: "Last December",
                  body: "Wrapping up the year.", mood: 4, words: 4),
        ]
    }

    // MARK: - Markdown

    @MainActor
    func testMarkdownContainsTitlesBodiesAndGrouping() {
        let md = ExportService.renderMarkdown(
            entries: sample(),
            tagsByEntry: ["E1": [Tag(rowId: 1, name: "gratitude", colorHex: "#7C5CFF")]],
            peopleByEntry: [:]
        )
        XCTAssertTrue(md.contains("# My PurpleDiary Journal"))
        XCTAssertTrue(md.contains("#### New year start"))
        XCTAssertTrue(md.contains("Feeling **great** today."))
        XCTAssertTrue(md.contains("#gratitude"))
        // Year headings for both years present.
        XCTAssertTrue(md.contains("## 2025"))
        XCTAssertTrue(md.contains("## 2026"))
        // Mood stars rendered for a rated entry.
        XCTAssertTrue(md.contains("★"))
    }

    @MainActor
    func testMarkdownEmptyJournal() {
        let md = ExportService.renderMarkdown(entries: [], tagsByEntry: [:], peopleByEntry: [:])
        XCTAssertTrue(md.contains("# My PurpleDiary Journal"))
        XCTAssertTrue(md.contains("No entries yet."))
    }

    // MARK: - HTML

    @MainActor
    func testHTMLIsSelfContained() {
        let html = ExportService.renderHTML(entries: sample(), tagsByEntry: [:], peopleByEntry: [:])
        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("<style>"), "CSS should be inlined")
        XCTAssertFalse(html.contains("http://"), "No external resources")
        XCTAssertTrue(html.contains("New year start"))
        XCTAssertTrue(html.contains("<strong>great</strong>"), "Inline markdown bold should render")
    }

    @MainActor
    func testHTMLEscapesUserContent() {
        let evil = entry("X", date: "2026-03-01T10:00:00Z",
                         title: "<script>alert(1)</script>",
                         body: "1 < 2 && 3 > 2")
        let html = ExportService.renderHTML(entries: [evil], tagsByEntry: [:], peopleByEntry: [:])
        XCTAssertFalse(html.contains("<script>alert(1)</script>"),
                       "User HTML must be escaped before embedding")
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertTrue(html.contains("&amp;&amp;"))
    }

    // MARK: - JSON

    @MainActor
    func testJSONRoundTripsAndCarriesSchemaVersion() throws {
        let people = [Person(id: "P1", name: "Sam", notes: "a friend")]
        let trackers = [
            TrackerTag(rowId: 7, name: "Water", unit: "cups", kind: .number, colorHex: "#3FA9F5"),
            TrackerTag(rowId: 8, name: "Exercise", unit: "", kind: .boolean, colorHex: "#3FB950"),
        ]
        let data = try ExportService.encodeJSON(
            entries: sample(),
            people: people,
            tagsByEntry: ["E1": [Tag(rowId: 1, name: "gratitude", colorHex: "#7C5CFF")]],
            peopleByEntry: ["E1": people],
            trackerTags: trackers,
            trackerValuesByEntry: ["E1": [7: 6, 8: 1]]
        )
        let decoded = try JSONDecoder().decode(ExportService.JournalExport.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, ExportService.jsonSchemaVersion)
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.app, "PurpleDiary")
        XCTAssertEqual(decoded.entryCount, 3)
        XCTAssertEqual(decoded.entries.count, 3)
        XCTAssertEqual(decoded.people.count, 1)
        XCTAssertEqual(decoded.trackers.count, 2)
        XCTAssertEqual(Set(decoded.trackers.map(\.name)), ["Water", "Exercise"])

        let e1 = try XCTUnwrap(decoded.entries.first { $0.id == "E1" })
        XCTAssertEqual(e1.title, "New year start")
        XCTAssertEqual(e1.tags, ["gratitude"])
        XCTAssertEqual(e1.people, ["P1"])
        XCTAssertEqual(e1.moodRating, 5)
        // Two tracker values logged on E1, sorted by tracker name (Exercise, Water).
        XCTAssertEqual(e1.trackers.map(\.tracker), ["Exercise", "Water"])
        XCTAssertEqual(e1.trackers.first { $0.tracker == "Water" }?.value, 6)
    }

    // MARK: - Grouping

    @MainActor
    func testGroupingIsChronologicalByYearThenMonth() {
        let groups = ExportService.groupByYearMonth(sample())
        XCTAssertEqual(groups.map(\.year), ["2025", "2026"])
        // 2026 has January then February.
        let y2026 = try? XCTUnwrap(groups.first { $0.year == "2026" })
        XCTAssertEqual(y2026?.months.map(\.label), ["January", "February"])
    }
}
