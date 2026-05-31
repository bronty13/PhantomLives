import XCTest
@testable import PurpleDiary

/// Phase-8 importers. The PurpleDiary path is exercised as a full export→parse
/// round-trip; the third-party parsers are checked against synthetic JSON in
/// each app's documented shape (real-file verification is left to the user).
@MainActor
final class ImportTests: XCTestCase {

    private func data(_ s: String) -> Data { Data(s.utf8) }

    // MARK: - PurpleDiary round-trip

    func testPurpleDiaryRoundTripPreservesJournalsMoodTags() throws {
        let entries = [
            entry("E1", journal: "Work", title: "Standup", mood: 4),
            entry("E2", journal: "Personal", title: "Walk", mood: 0),
        ]
        let workJournal = Journal(id: "jW", name: "Work", colorHex: "#fff", symbol: "book", isHidden: false, sortOrder: 0, createdAt: "")
        let personalJournal = Journal(id: "jP", name: "Personal", colorHex: "#fff", symbol: "book", isHidden: false, sortOrder: 1, createdAt: "")
        let json = try ExportService.encodeJSON(
            entries: entries,
            people: [],
            tagsByEntry: ["E1": [Tag(rowId: 1, name: "focus", colorHex: "#fff")]],
            peopleByEntry: [:],
            journals: [workJournal, personalJournal]
        )
        let bundle = try ImportService.parse(json, format: .auto)
        XCTAssertEqual(bundle.sourceName, "PurpleDiary")
        XCTAssertEqual(Set(bundle.journals.map(\.name)), ["Work", "Personal"])
        XCTAssertEqual(bundle.totalEntries, 2)
        let work = try XCTUnwrap(bundle.journals.first { $0.name == "Work" })
        XCTAssertEqual(work.entries.first?.title, "Standup")
        XCTAssertEqual(work.entries.first?.moodRating, 4)
        XCTAssertEqual(work.entries.first?.tags, ["focus"])
    }

    func testApplyAddsEntriesAndIsAdditive() throws {
        let bundle = ImportService.Bundle(sourceName: "Test", journals: [
            .init(name: "Imported Trips", entries: [
                .init(date: "2026-01-01T10:00:00Z", title: "Trip", body: "hi", moodRating: 3, tags: ["travel"])
            ])
        ])
        let before = try DatabaseService.shared.fetchAllEntries().count
        let added = try ImportService.apply(bundle)
        XCTAssertEqual(added, 1)
        XCTAssertEqual(try DatabaseService.shared.fetchAllEntries().count, before + 1)
        // A destination journal was created and the tag exists.
        XCTAssertTrue(try DatabaseService.shared.fetchAllJournals().contains { $0.name == "Imported Trips" })
        XCTAssertTrue(try DatabaseService.shared.fetchAllTags().contains { $0.name == "travel" })
    }

    // MARK: - Third-party parsers (documented shapes)

    func testParseDayOne() throws {
        let json = data("""
        { "metadata": {"version":"1.0"},
          "entries": [
            { "uuid":"A","creationDate":"2026-05-31T09:00:00Z","text":"# Hi\\nbody","tags":["a","b"] },
            { "uuid":"B","creationDate":"2026-05-30T09:00:00Z","text":"second" }
          ] }
        """)
        let b = try ImportService.parse(json, format: .dayOne)
        XCTAssertEqual(b.sourceName, "Day One")
        XCTAssertEqual(b.totalEntries, 2)
        XCTAssertEqual(b.journals.first?.entries.first?.tags, ["a", "b"])
        XCTAssertEqual(b.journals.first?.entries.first?.body, "# Hi\nbody")
    }

    func testParseJourneyArray() throws {
        let json = data("""
        [ { "date_journal": 1748682000000, "text": "from journey", "tags": ["x"] } ]
        """)
        let b = try ImportService.parse(json, format: .journey)
        XCTAssertEqual(b.sourceName, "Journey")
        XCTAssertEqual(b.totalEntries, 1)
        XCTAssertEqual(b.journals.first?.entries.first?.body, "from journey")
        XCTAssertFalse(b.journals.first?.entries.first?.date.isEmpty ?? true)  // ms → ISO
    }

    func testParseDiariumBareArray() throws {
        let json = data("""
        [ { "date":"2026-05-31T00:00:00Z","title":"T","text":"diarium body","tags":["t"] } ]
        """)
        let b = try ImportService.parse(json, format: .diarium)
        XCTAssertEqual(b.sourceName, "Diarium")
        XCTAssertEqual(b.journals.first?.entries.first?.title, "T")
        XCTAssertEqual(b.journals.first?.entries.first?.body, "diarium body")
    }

    func testAutoDetectFallsBackAndThrowsOnGarbage() {
        XCTAssertThrowsError(try ImportService.parse(data("{\"nope\":true}"), format: .auto))
    }

    // MARK: - Helpers

    private let iso = ISO8601DateFormatter()
    private func entry(_ id: String, journal: String, title: String, mood: Int) -> Entry {
        var e = Entry.newDraft(title: title)
        e.id = id
        e.moodRating = mood
        // journalId is set by the export's journals array mapping in the test via
        // a matching name; assign deterministically by using the journal name as id-free.
        e.journalId = journal == "Work" ? "jW" : "jP"
        return e
    }
}
