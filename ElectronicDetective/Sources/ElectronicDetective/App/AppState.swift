import SwiftUI
import Combine

/// Top-level observable store. Owns the in-flight `GameSession`, the settings
/// sub-store, and the persistence wiring (auto-save on every mutation,
/// auto-backup on launch, history append on game-end).
@MainActor
final class AppState: ObservableObject {

    @Published var session: GameSession? {
        didSet { persistSession() }
    }
    @Published var errorMessage: String?
    @Published var verdictDismissed: Bool = false
    @Published var handoffPending: Bool = false

    let settings = AppSettings()

    /// Suppressed inside `init` (we don't want to re-persist the freshly
    /// loaded session right back to disk during initialization) and around
    /// the bulk restore path.
    private var suspendPersistence = true

    init() {
        BackupService.runOnLaunchIfDue(settings: settings)

        SoundBank.shared.audioEnabled    = settings.audioEnabled
        SoundBank.shared.keyClickEnabled = settings.keyClickEnabled

        // Restore the last in-flight session, if any. If the previous run
        // ended on a verdict, mark it dismissed so the overlay doesn't
        // re-pop on every launch — the user already saw it.
        if let restored = try? DatabaseService.shared.loadCurrentSession() {
            session = restored
            if restored.outcome != .inProgress {
                verdictDismissed = true
            }
        }
        suspendPersistence = false
    }

    private func persistSession() {
        guard !suspendPersistence else { return }
        do { try DatabaseService.shared.saveCurrentSession(session) }
        catch { NSLog("ElectronicDetective: saveCurrentSession failed — \(error)") }
    }

    // MARK: - Session lifecycle

    func startNewGame(difficulty: Difficulty, playerNames: [String], seed: UInt64? = nil) {
        do {
            let gameCase = try CaseGenerator.generate(seed: seed)
            session = GameSession.new(
                difficulty: difficulty,
                playerNames: playerNames,
                gameCase: gameCase
            )
            verdictDismissed = false
            handoffPending = false
            playCue(.bong)
        } catch {
            errorMessage = "Couldn't generate a case: \(error.localizedDescription)"
        }
    }

    func endTurn() {
        advanceToNextActiveSeat(raiseCurtain: true)
    }

    private func advanceToNextActiveSeat(raiseCurtain: Bool) {
        guard var s = session, let next = s.nextActiveSeat() else { return }
        let isMulti = s.players.count > 1
        s.currentSeat = next
        s.privateQuestionsAskedThisTurn = 0
        session = s
        if isMulti && raiseCurtain && s.outcome == .inProgress {
            handoffPending = true
        }
    }

    // MARK: - Interrogation

    @discardableResult
    func askWhereWereYou(suspectId: Int) -> Interrogator.Answer? {
        guard let game = session else { return nil }
        let ans = Interrogator.answer(question: .whereWereYou, suspectId: suspectId, in: game.gameCase)
        autoRecord(answer: ans, suspectId: suspectId)
        return ans
    }

    @discardableResult
    func askFingerprint(suspectId: Int) -> Interrogator.Answer? {
        guard var game = session else { return nil }
        guard game.privateQuestionsAskedThisTurn < game.difficulty.privateQuestionsPerTurn else {
            return nil
        }
        let ans = Interrogator.answer(question: .fingerprintParity, suspectId: suspectId, in: game.gameCase)
        game.privateQuestionsAskedThisTurn += 1
        session = game
        autoRecord(answer: ans, suspectId: suspectId)
        return ans
    }

    private func autoRecord(answer: Interrogator.Answer, suspectId: Int) {
        guard settings.transcriptionMode == .auto else { return }
        guard var s = session,
              let pi = s.players.firstIndex(where: { $0.seat == s.currentSeat })
        else { return }
        switch answer {
        case .location(let loc):
            s.players[pi].notepad.locationsBySuspect[suspectId] = loc
        case .parity(let p):
            s.players[pi].notepad.fingerprintParity = p
        case .dontKnow, .dead:
            break
        }
        session = s
    }

    // MARK: - Accusation

    @discardableResult
    func accuse(suspectId: Int) -> Accuser.AccusationResult? {
        guard var s = session else { return nil }
        let result = Accuser.accuse(seat: s.currentSeat, suspectId: suspectId, in: &s)
        session = s

        switch result {
        case .correct:
            playCue(.siren)
            appendHistoryIfNeeded()
        case .wrong:
            playCue(.gunshot)
            if s.outcome == .allWrong {
                playCue(.dirge)
                appendHistoryIfNeeded()
            } else {
                advanceToNextActiveSeat(raiseCurtain: true)
            }
        case .alreadyAccused:
            break
        }
        verdictDismissed = false
        return result
    }

    private func appendHistoryIfNeeded() {
        guard let s = session, s.outcome != .inProgress, s.finishedAt != nil else { return }
        do { try DatabaseService.shared.appendHistory(s) }
        catch { NSLog("ElectronicDetective: appendHistory failed — \(error)") }
    }

    // MARK: - Audio plumbing

    func playCue(_ cue: AssetResolver.AudioCue) {
        SoundBank.shared.audioEnabled    = settings.audioEnabled
        SoundBank.shared.keyClickEnabled = settings.keyClickEnabled
        SoundBank.shared.play(cue)
    }

    // MARK: - Settings-driven actions

    /// Reset the in-flight game without quitting the app. Used by the
    /// "Forget current game" button in Settings.
    func forgetCurrentSession() {
        session = nil
        verdictDismissed = false
        handoffPending = false
    }
}
