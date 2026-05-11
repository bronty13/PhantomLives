import Foundation

/// Validates an `I ACCUSE` action and mutates the `GameSession` accordingly.
///
/// Each player gets exactly one accusation attempt per game. A wrong guess
/// eliminates the player for the rest of the game. A right guess ends the
/// game with `.solved`. If every player accuses incorrectly the game ends
/// `.allWrong` and the console reveals the murderer.
enum Accuser {

    enum AccusationResult: Equatable {
        case correct(suspectId: Int)
        case wrong(suspectId: Int, eliminatedSeat: Int)
        case alreadyAccused
    }

    @discardableResult
    static func accuse(seat: Int, suspectId: Int, in session: inout GameSession) -> AccusationResult {
        guard let idx = session.players.firstIndex(where: { $0.seat == seat }) else {
            return .alreadyAccused   // defensive
        }
        if session.players[idx].accusation != nil {
            return .alreadyAccused
        }

        session.players[idx].accusation = suspectId

        if suspectId == session.gameCase.murdererId {
            session.players[idx].accusationCorrect = true
            session.outcome = .solved
            session.finishedAt = Date()
            return .correct(suspectId: suspectId)
        }

        session.players[idx].accusationCorrect = false
        session.players[idx].eliminated = true

        // If every player has now accused (and we landed here, so none was correct),
        // the game ends as allWrong.
        if session.players.allSatisfy({ $0.accusation != nil }) {
            session.outcome = .allWrong
            session.finishedAt = Date()
        }

        return .wrong(suspectId: suspectId, eliminatedSeat: seat)
    }
}
