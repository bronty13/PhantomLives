import SwiftUI

/// Full-window overlay shown when `session.outcome != .inProgress`. Mirrors
/// the moment the original console reveals the answer and plays the
/// appropriate audio cue (siren / gunshot / dirge). The cue itself is fired
/// from `AppState` on state transition, not from here — so the audio plays
/// even if the view never gets a chance to render.
struct VerdictView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings
    let onDismiss: () -> Void

    private var session: GameSession? { appState.session }

    var body: some View {
        ZStack {
            Color.black.opacity(0.86).ignoresSafeArea()
                .transition(.opacity)

            VStack(spacing: 22) {
                Text(headline)
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(headlineColor)
                    .shadow(color: headlineColor.opacity(0.7), radius: 16)
                if let s = session, shouldReveal(s) {
                    revealBox(for: s)
                }
                actions
            }
            .padding(36)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.10, green: 0.07, blue: 0.05))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(headlineColor.opacity(0.5), lineWidth: 2))
                    .shadow(color: .black.opacity(0.6), radius: 30)
            )
            .frame(maxWidth: 640)
            .padding(24)
        }
    }

    // MARK: - Pieces

    private var headline: String {
        guard let s = session else { return "" }
        switch s.outcome {
        case .solved:   return "CASE SOLVED"
        case .allWrong: return "CASE COLD"
        case .abandoned: return "GAME OVER"
        case .inProgress: return ""
        }
    }

    private var headlineColor: Color {
        guard let s = session else { return .white }
        switch s.outcome {
        case .solved:   return Color(red: 0.55, green: 1.0, blue: 0.55)
        case .allWrong, .abandoned: return Color(red: 1.0, green: 0.35, blue: 0.25)
        case .inProgress: return .white
        }
    }

    /// Hide the full reveal if the user disabled `revealOnLoss` and the game
    /// ended in a loss — preserves the option to retry the same scenario.
    private func shouldReveal(_ s: GameSession) -> Bool {
        switch s.outcome {
        case .solved: return true
        case .allWrong, .abandoned: return settings.revealOnLoss
        case .inProgress: return false
        }
    }

    private func revealBox(for s: GameSession) -> some View {
        let murderer = s.gameCase.murderer
        return VStack(spacing: 8) {
            Text("THE MURDERER")
                .font(.caption).bold()
                .foregroundStyle(.white.opacity(0.55))
            Text("#\(murderer.id) — \(murderer.name)")
                .font(.title3).bold()
                .foregroundStyle(.white)
            Text(murderer.occupation)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            Divider().overlay(.white.opacity(0.2)).padding(.vertical, 4)
            HStack(spacing: 18) {
                fact("WAS AT", s.gameCase.suspectLocations[murderer.id]?.displayName ?? "—")
                fact("BODY FOUND", s.gameCase.victimLocation.displayName)
                fact("PRINTS", s.gameCase.fingerprintParity.rawValue.uppercased())
            }
            Text("Weapons: " + s.gameCase.weapons
                    .map { "\($0.caliber.displayName) at \($0.location.displayName)" }
                    .joined(separator: "    •    "))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 4)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.05)))
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.55))
            Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(.white)
        }
    }

    private var actions: some View {
        HStack(spacing: 14) {
            Button {
                appState.startNewGame(difficulty: appState.session?.difficulty ?? .gumshoe,
                                      playerNames: appState.session?.players.map(\.name) ?? ["Detective"])
                onDismiss()
            } label: {
                Label("New Game", systemImage: "play.fill")
                    .frame(minWidth: 110)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

            Button {
                onDismiss()
            } label: {
                Label("Close", systemImage: "xmark")
                    .frame(minWidth: 80)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
        }
    }
}
