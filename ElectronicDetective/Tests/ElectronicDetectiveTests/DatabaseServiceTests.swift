import XCTest
@testable import ElectronicDetective

/// Round-trip the persistence surface against a temp-dir DB. Uses the
/// `init(path:)` test seam so tests don't collide with the user's real
/// `~/Library/Application Support/ElectronicDetective/database.sqlite`.
@MainActor
final class DatabaseServiceTests: XCTestCase {

    private func makeDB() throws -> (DatabaseService, URL) {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ed-tests-\(UUID().uuidString).sqlite")
        let db = try DatabaseService(path: tmp.path)
        return (db, tmp)
    }

    func testRoundTripCurrentSession() throws {
        let (db, _) = try makeDB()
        XCTAssertNil(try db.loadCurrentSession(), "fresh DB starts with no session")

        let gc = try CaseGenerator.generate(seed: 42)
        let s = GameSession.new(difficulty: .sleuth, playerNames: ["A", "B"], gameCase: gc)
        try db.saveCurrentSession(s)

        let loaded = try db.loadCurrentSession()
        XCTAssertEqual(loaded?.id, s.id)
        XCTAssertEqual(loaded?.difficulty, .sleuth)
        XCTAssertEqual(loaded?.players.count, 2)
        XCTAssertEqual(loaded?.gameCase.murdererId, s.gameCase.murdererId)
    }

    func testSavingNilClearsCurrentSession() throws {
        let (db, _) = try makeDB()
        let gc = try CaseGenerator.generate(seed: 1)
        let s = GameSession.new(difficulty: .gumshoe, playerNames: ["A"], gameCase: gc)
        try db.saveCurrentSession(s)
        try db.saveCurrentSession(nil)
        XCTAssertNil(try db.loadCurrentSession())
    }

    func testHistoryAppendAndFetch() throws {
        let (db, _) = try makeDB()
        XCTAssertEqual(try db.fetchHistory().count, 0)

        let gc = try CaseGenerator.generate(seed: 99)
        var s = GameSession.new(difficulty: .masterDetective, playerNames: ["P"], gameCase: gc)
        // Manually stamp a terminal outcome.
        s.outcome = .solved
        s.finishedAt = Date()
        try db.appendHistory(s)

        let hist = try db.fetchHistory()
        XCTAssertEqual(hist.count, 1)
        XCTAssertEqual(hist[0].outcome, .solved)
        XCTAssertEqual(hist[0].difficulty, .masterDetective)
        XCTAssertEqual(hist[0].playerCount, 1)
        XCTAssertEqual(hist[0].murdererId, s.gameCase.murdererId)
    }

    /// Calling `appendHistory` twice with the same session must NOT duplicate
    /// the row — the AppState's accusation path may fire it twice on quick
    /// state transitions and we'd rather de-dupe in the service.
    func testHistoryAppendIsIdempotent() throws {
        let (db, _) = try makeDB()
        let gc = try CaseGenerator.generate(seed: 7)
        var s = GameSession.new(difficulty: .gumshoe, playerNames: ["P"], gameCase: gc)
        s.outcome = .allWrong
        s.finishedAt = Date()
        try db.appendHistory(s)
        try db.appendHistory(s)
        XCTAssertEqual(try db.fetchHistory().count, 1)
    }

    /// In-progress sessions never enter the history table.
    func testHistoryIgnoresInProgressSessions() throws {
        let (db, _) = try makeDB()
        let gc = try CaseGenerator.generate(seed: 11)
        let s  = GameSession.new(difficulty: .sleuth, playerNames: ["A"], gameCase: gc)
        try db.appendHistory(s)
        XCTAssertEqual(try db.fetchHistory().count, 0)
    }

    /// Two databases opened in sequence at the same path see the same data —
    /// migrations are idempotent across processes.
    func testReopenSeesPersistedData() throws {
        let (db1, url) = try makeDB()
        let gc = try CaseGenerator.generate(seed: 2024)
        let s = GameSession.new(difficulty: .gumshoe, playerNames: ["X"], gameCase: gc)
        try db1.saveCurrentSession(s)

        let db2 = try DatabaseService(path: url.path)
        let loaded = try db2.loadCurrentSession()
        XCTAssertEqual(loaded?.id, s.id)
    }
}
