import XCTest
@testable import ElectronicDetective

/// Hot-seat flow assertions: end-of-turn seat advancement, handoff curtain
/// raising in multi-player, auto-advance after a wrong accusation. These
/// guard the multi-player UX from regressions in the engine wiring.
@MainActor
final class TurnFlowTests: XCTestCase {

    /// `endTurn` in solo play advances the (single) seat back to itself and
    /// must NOT raise the hot-seat curtain.
    func testSoloEndTurnDoesNotRaiseCurtain() async throws {
        let app = AppState()
        app.startNewGame(difficulty: .gumshoe, playerNames: ["P1"])
        XCTAssertFalse(app.handoffPending)
        app.endTurn()
        XCTAssertFalse(app.handoffPending)
        XCTAssertEqual(app.session?.currentSeat, 1)
    }

    /// In a 3-player game, end-of-turn moves to seat 2 and raises the curtain.
    func testMultiplayerEndTurnRaisesCurtainAndAdvancesSeat() async throws {
        let app = AppState()
        app.startNewGame(difficulty: .sleuth, playerNames: ["A", "B", "C"])
        XCTAssertEqual(app.session?.currentSeat, 1)
        app.endTurn()
        XCTAssertEqual(app.session?.currentSeat, 2)
        XCTAssertTrue(app.handoffPending)
        // Simulate the user dismissing the curtain.
        app.handoffPending = false
        app.endTurn()
        XCTAssertEqual(app.session?.currentSeat, 3)
        XCTAssertTrue(app.handoffPending)
    }

    /// `endTurn` skips eliminated seats — after seat 2 is out, seat 1's
    /// end-of-turn jumps directly to seat 3.
    func testEndTurnSkipsEliminatedSeats() async throws {
        let app = AppState()
        app.startNewGame(difficulty: .sleuth, playerNames: ["A", "B", "C"])
        // Burn seat 2 with a known-wrong accusation.
        let murderer = app.session!.gameCase.murdererId
        let victim   = app.session!.gameCase.victimId
        let wrongId  = (1...20).first { $0 != murderer && $0 != victim }!
        app.session!.currentSeat = 2
        _ = app.accuse(suspectId: wrongId)   // seat 2 eliminated
        // Auto-advance moved us to seat 3 already (see test below); manually
        // park back at seat 1 and end-turn.
        app.session!.currentSeat = 1
        app.handoffPending = false
        app.endTurn()
        XCTAssertEqual(app.session?.currentSeat, 3, "must skip eliminated seat 2")
    }

    /// A wrong accusation auto-advances to the next active seat AND raises
    /// the curtain — the eliminated player can't keep holding the desk.
    func testWrongAccusationAutoAdvancesAndRaisesCurtain() async throws {
        let app = AppState()
        app.startNewGame(difficulty: .sleuth, playerNames: ["A", "B"])
        let murderer = app.session!.gameCase.murdererId
        let victim   = app.session!.gameCase.victimId
        let wrongId  = (1...20).first { $0 != murderer && $0 != victim }!

        XCTAssertEqual(app.session?.currentSeat, 1)
        let result = app.accuse(suspectId: wrongId)
        XCTAssertEqual(result, .wrong(suspectId: wrongId, eliminatedSeat: 1))
        XCTAssertTrue(app.session!.players[0].eliminated)
        XCTAssertEqual(app.session?.currentSeat, 2, "must advance to next active seat after wrong accusation")
        XCTAssertTrue(app.handoffPending, "curtain must raise so seat 2 takes over cleanly")
    }

    /// When the wrong accusation also ends the game (last player out), no
    /// curtain raises — the verdict overlay takes over instead.
    func testFinalWrongAccusationDoesNotRaiseCurtain() async throws {
        let app = AppState()
        app.startNewGame(difficulty: .gumshoe, playerNames: ["A", "B"])
        let murderer = app.session!.gameCase.murdererId
        let victim   = app.session!.gameCase.victimId
        let wrongs   = (1...20).filter { $0 != murderer && $0 != victim }

        _ = app.accuse(suspectId: wrongs[0])     // seat 1 out → advance to seat 2
        XCTAssertEqual(app.session?.currentSeat, 2)
        app.handoffPending = false               // user dismissed the curtain

        _ = app.accuse(suspectId: wrongs[1])     // seat 2 out → game .allWrong
        XCTAssertEqual(app.session?.outcome, .allWrong)
        XCTAssertFalse(app.handoffPending, "no handoff once the game is over")
    }
}
