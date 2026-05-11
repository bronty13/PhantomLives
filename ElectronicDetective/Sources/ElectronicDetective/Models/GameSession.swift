import Foundation

/// One in-flight game. Created by the setup view, mutated turn-by-turn by the
/// `ConsoleViewModel`, persisted at end-of-game.
struct GameSession: Codable, Sendable {
    struct Player: Codable, Hashable, Sendable {
        let seat: Int                  // 1...playerCount
        var name: String
        var notepad: PlayerNotepad
        var eliminated: Bool
        var accusation: Int?           // suspect id the player accused (nil = no accusation yet)
        var accusationCorrect: Bool?   // nil until they accuse
    }

    enum Outcome: String, Codable, Sendable {
        case inProgress
        case solved          // some player got it right
        case allWrong        // every player accused and all were wrong
        case abandoned
    }

    let id: UUID
    let startedAt: Date
    var finishedAt: Date?

    let difficulty: Difficulty
    var players: [Player]
    var currentSeat: Int               // 1...playerCount
    let gameCase: GameCase

    var outcome: Outcome
    /// Per-turn count of private questions asked by the current player —
    /// reset when the seat changes. Bounded by `difficulty.privateQuestionsPerTurn`.
    var privateQuestionsAskedThisTurn: Int

    var currentPlayer: Player? {
        players.first { $0.seat == currentSeat }
    }

    /// The active (non-eliminated) player seats in turn order, starting from
    /// the current seat and wrapping.
    func nextActiveSeat() -> Int? {
        let count = players.count
        for offset in 1...count {
            let seat = ((currentSeat - 1 + offset) % count) + 1
            if let p = players.first(where: { $0.seat == seat }), !p.eliminated {
                return seat
            }
        }
        return nil
    }

    static func new(difficulty: Difficulty, playerNames: [String], gameCase: GameCase) -> GameSession {
        let players = playerNames.enumerated().map { idx, name in
            Player(seat: idx + 1,
                   name: name.isEmpty ? "Player \(idx + 1)" : name,
                   notepad: .empty,
                   eliminated: false,
                   accusation: nil,
                   accusationCorrect: nil)
        }
        return GameSession(
            id: UUID(),
            startedAt: Date(),
            finishedAt: nil,
            difficulty: difficulty,
            players: players,
            currentSeat: 1,
            gameCase: gameCase,
            outcome: .inProgress,
            privateQuestionsAskedThisTurn: 0
        )
    }
}
