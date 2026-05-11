import XCTest
import GRDB
@testable import PurpleTracker

@MainActor
final class NotesMigrationTests: XCTestCase {

    func testV8CreatesNoteTables() throws {
        let q = try DatabaseQueue()
        try DatabaseService.applyMigrations(to: q)
        try q.read { db in
            XCTAssertTrue(try db.tableExists("note_type"))
            XCTAssertTrue(try db.tableExists("generic_note"))
        }
    }

    func testV8SeedsDefaultNoteTypes() throws {
        let q = try DatabaseQueue()
        try DatabaseService.applyMigrations(to: q)
        let names: [String] = try q.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM note_type ORDER BY sort_order")
        }
        for expected in ["Staff", "Architecture", "Team", "SCRUM", "Third Party"] {
            XCTAssertTrue(names.contains(expected), "missing default note type: \(expected)")
        }
    }

    func testRTFRoundtrip() throws {
        let s = NSMutableAttributedString(string: "Hello, world.")
        s.addAttribute(.font,
                       value: NSFont.boldSystemFont(ofSize: 14),
                       range: NSRange(location: 0, length: 5))
        let data = s.toRTFData()
        XCTAssertNotNil(data)
        let restored = NSAttributedString.fromRTFData(data)
        XCTAssertEqual(restored.string, "Hello, world.")
    }
}
