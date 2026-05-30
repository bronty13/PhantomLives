import XCTest
import GRDB
@testable import PurpleDiary

final class ModelTests: XCTestCase {

    /// Entry Codable round-trips through GRDB column mapping.
    @MainActor
    func testEntryRoundTripWithContextColumns() throws {
        let queue = try DatabaseQueue()
        try DatabaseService.applyMigrations(to: queue)

        try queue.write { db in
            var e = Entry.newDraft(title: "Trip")
            e.id = "geo-1"
            e.latitude = 37.7749
            e.longitude = -122.4194
            e.placeName = "San Francisco"
            e.weatherSummary = "Foggy"
            e.temperatureC = 14.5
            e.mood = .great
            try e.insert(db)
        }
        try queue.read { db in
            let e = try Entry.fetchOne(db, key: "geo-1")
            XCTAssertEqual(e?.placeName, "San Francisco")
            XCTAssertEqual(e?.temperatureC, 14.5)
            XCTAssertEqual(e?.mood, .great)
        }
    }

    func testWordCount() {
        XCTAssertEqual(Entry.countWords(in: ""), 0)
        XCTAssertEqual(Entry.countWords(in: "   \n  "), 0)
        XCTAssertEqual(Entry.countWords(in: "hello world"), 2)
        XCTAssertEqual(Entry.countWords(in: "one\ntwo\tthree   four"), 4)
    }

    func testRefreshWordCountStampsOnEntry() {
        var e = Entry.newDraft()
        e.bodyMarkdown = "a b c d e"
        e.refreshWordCount()
        XCTAssertEqual(e.wordCount, 5)
    }

    func testMoodRawValueMapping() {
        XCTAssertEqual(Mood(rawValue: 0), .unset)
        XCTAssertEqual(Mood.great.rawValue, 5)
        XCTAssertEqual(Mood.great.filledStars, 5)
        XCTAssertEqual(Mood.unset.filledStars, 0)
    }
}
