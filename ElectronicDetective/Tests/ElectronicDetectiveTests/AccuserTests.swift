import XCTest
@testable import ElectronicDetective

final class AccuserTests: XCTestCase {

    private func makeSession(seed: UInt64 = 1, players: Int = 3) throws -> GameSession {
        let gc = try CaseGenerator.generate(seed: seed)
        let names = (1...players).map { "P\($0)" }
        return GameSession.new(difficulty: .gumshoe, playerNames: names, gameCase: gc)
    }

    func testCorrectAccusationSolvesGame() throws {
        var s = try makeSession()
        let result = Accuser.accuse(seat: 1, suspectId: s.gameCase.murdererId, in: &s)
        XCTAssertEqual(result, .correct(suspectId: s.gameCase.murdererId))
        XCTAssertEqual(s.outcome, .solved)
        XCTAssertNotNil(s.finishedAt)
        XCTAssertEqual(s.players[0].accusationCorrect, true)
        XCTAssertFalse(s.players[0].eliminated)
    }

    func testWrongAccusationEliminatesOnlyTheAccuser() throws {
        var s = try makeSession()
        let wrongId = (1...20).first { $0 != s.gameCase.murdererId && $0 != s.gameCase.victimId }!
        let result = Accuser.accuse(seat: 2, suspectId: wrongId, in: &s)
        XCTAssertEqual(result, .wrong(suspectId: wrongId, eliminatedSeat: 2))
        XCTAssertEqual(s.players[1].eliminated, true)
        XCTAssertEqual(s.players[0].eliminated, false)
        XCTAssertEqual(s.players[2].eliminated, false)
        XCTAssertEqual(s.outcome, .inProgress)
    }

    /// Players get exactly one attempt — a second accusation by the same seat
    /// is rejected.
    func testRepeatedAccusationByOnePlayerIsRejected() throws {
        var s = try makeSession()
        let wrongId = (1...20).first { $0 != s.gameCase.murdererId && $0 != s.gameCase.victimId }!
        _ = Accuser.accuse(seat: 1, suspectId: wrongId, in: &s)
        let again = Accuser.accuse(seat: 1, suspectId: s.gameCase.murdererId, in: &s)
        XCTAssertEqual(again, .alreadyAccused)
        XCTAssertEqual(s.outcome, .inProgress)
    }

    /// When every player has accused wrong, the game ends `.allWrong`.
    func testAllPlayersWrongEndsGame() throws {
        var s = try makeSession(seed: 2, players: 2)
        let wrongIds = (1...20).filter { $0 != s.gameCase.murdererId && $0 != s.gameCase.victimId }
        _ = Accuser.accuse(seat: 1, suspectId: wrongIds[0], in: &s)
        _ = Accuser.accuse(seat: 2, suspectId: wrongIds[1], in: &s)
        XCTAssertEqual(s.outcome, .allWrong)
        XCTAssertNotNil(s.finishedAt)
        XCTAssertTrue(s.players.allSatisfy { $0.eliminated })
    }
}
