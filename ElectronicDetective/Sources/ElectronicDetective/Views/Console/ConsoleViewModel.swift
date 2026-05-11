import Foundation
import SwiftUI

/// State machine for the console's input loop. Lives between the keypad
/// (`KeypadView`) and the game engine (`AppState`). Mirrors the original
/// console's prompt sequence at startup — ON → PL? (player count, 1–4) →
/// DIF? (difficulty, 1–3) — and the in-game vocabulary: SUSPECT + digits +
/// ENTER for "where were you", PRIVATE QUESTION + digits + ENTER for
/// fingerprint parity, and I ACCUSE + digits + ENTER for the accusation.
@MainActor
final class ConsoleViewModel: ObservableObject {

    enum Mode {
        case idle                       // READY — waiting for a function key
        case awaitingPlayerCount        // post-ON, before game start
        case awaitingDifficulty
        case awaitingSuspectId
        case awaitingPrivateQuestionId
        case awaitingAccusationId
    }

    @Published var line: LEDLine = .ready
    @Published private(set) var mode: Mode = .idle

    private var buffer: String = ""
    /// Carried across the PL? → DIF? prompt sequence so the eventual
    /// `startNewGame` call gets both values together.
    private var pendingPlayerCount: Int?
    private weak var appState: AppState?

    func bind(appState: AppState) {
        self.appState = appState
    }

    func handle(key: ConsoleKey) {
        // Every key produces a click; the function-specific cue (bong on ON)
        // is layered on top.
        appState?.playCue(.key)

        switch key {
        case .onOff:
            handleOn()
        case .clear:
            buffer = ""; line = .ready; mode = .idle
        case .digit(let n):
            buffer.append("\(n)")
            line = .echo(buffer)
        case .suspect:
            requireGame { buffer = ""; mode = .awaitingSuspectId; line = .prompt("SUS?") }
        case .privateQuestion:
            requireGame { buffer = ""; mode = .awaitingPrivateQuestionId; line = .prompt("PQ?") }
        case .iAccuse:
            requireGame { buffer = ""; mode = .awaitingAccusationId; line = .prompt("ACC?") }
        case .enter:
            commit()
        case .endTurn:
            requireGame { appState?.endTurn(); buffer = ""; mode = .idle; line = .ready }
        case .readout:
            line = .echo(buffer.isEmpty ? "READY" : buffer)
        }
    }

    // MARK: - ON / startup prompts

    private func handleOn() {
        if let app = appState, app.session != nil, app.session?.outcome == .inProgress {
            // Game in progress — ON is a no-op acknowledgment. Replays the
            // 3-bong cue so the user gets feedback without nuking state.
            appState?.playCue(.bong)
            return
        }
        // No game (or one already finished) — enter the prompt sequence.
        buffer = ""
        pendingPlayerCount = nil
        mode = .awaitingPlayerCount
        line = .prompt("PL?")
    }

    // MARK: - ENTER dispatch

    private func commit() {
        guard let app = appState else { return }

        switch mode {
        case .idle:
            line = .error("FN")
            buffer = ""

        case .awaitingPlayerCount:
            guard let n = Int(buffer), (1...4).contains(n) else {
                line = .error("PL"); buffer = ""; return
            }
            pendingPlayerCount = n
            buffer = ""
            mode = .awaitingDifficulty
            line = .prompt("DIF?")

        case .awaitingDifficulty:
            guard let n = Int(buffer), let diff = Difficulty(rawValue: n) else {
                line = .error("DIF"); buffer = ""; return
            }
            let count = pendingPlayerCount ?? 1
            let names = (1...count).map { "Player \($0)" }
            app.startNewGame(difficulty: diff, playerNames: names)
            buffer = ""; mode = .idle
            // LED announcement of where the body was found — the only
            // bookkeeping the console traditionally hands the players at
            // game start. Players record it (or read it auto-recorded into
            // their pad in `.auto` mode by `AppState.startNewGame`'s side
            // effects — actually that's not auto-recorded by current code,
            // since the body location is a fact, not an answer; the player
            // copies it manually from the LED).
            if let bodyLoc = app.session?.gameCase.victimLocation {
                line = .answer("BDY \(bodyLoc.code)")
            } else {
                line = .ready
            }

        case .awaitingSuspectId:
            guard let id = parsedSuspectId() else { line = .error("ID"); return }
            switch app.askWhereWereYou(suspectId: id) {
            case .some(.location(let loc)): line = .answer(loc.code)
            case .some(.dead):              line = .answer("DEAD")
            case .some(.dontKnow), .none:   line = .answer("---")
            case .some(.parity):            line = .error("?")
            }
            mode = .idle

        case .awaitingPrivateQuestionId:
            guard let id = parsedSuspectId() else { line = .error("ID"); return }
            switch app.askFingerprint(suspectId: id) {
            case .some(.parity(let p)):     line = .answer(p == .odd ? "ODD" : "EVEN")
            case .some(.dontKnow):          line = .answer("IDK")
            case .some(.dead):              line = .answer("DEAD")
            case .none:                     line = .error("LIM")    // turn-budget exhausted
            case .some(.location):          line = .error("?")
            }
            mode = .idle

        case .awaitingAccusationId:
            guard let id = parsedSuspectId() else { line = .error("ID"); return }
            switch app.accuse(suspectId: id) {
            case .some(.correct): line = .verdict(correct: true)
            case .some(.wrong):   line = .verdict(correct: false)
            case .some(.alreadyAccused), .none:
                line = .error("DUP")
            }
            mode = .idle
        }
    }

    private func parsedSuspectId() -> Int? {
        defer { buffer = "" }
        guard let id = Int(buffer), (1...20).contains(id) else { return nil }
        return id
    }

    /// Block a function key (SUSPECT/PQ/ACC/END) until a game is in flight.
    private func requireGame(_ action: () -> Void) {
        guard appState?.session != nil else {
            line = .error("OFF")
            return
        }
        action()
    }
}
