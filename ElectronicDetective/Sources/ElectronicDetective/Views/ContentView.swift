import SwiftUI

/// The on-screen desk. Notepad on the left, console centered, rolodex on
/// the right. Toolbar buttons open the rules booklet and the game history.
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var assets: AssetResolver
    @State private var rulesPresented = false
    @State private var historyPresented = false

    var body: some View {
        ZStack {
            DeskBackground()
            HStack(spacing: 18) {
                CaseFactSheetView()
                    .frame(width: 320)
                VStack(spacing: 16) {
                    ConsoleView()
                    BriefingStrip()
                }
                .frame(maxWidth: .infinity)
                SuspectRolodexView()
                    .frame(width: 300)
            }
            .padding(20)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        historyPresented = true
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.white)

                    Button {
                        rulesPresented = true
                    } label: {
                        Label("Rules", systemImage: "book.closed")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.white)
                    .padding(.trailing, 18)
                }
                .padding(.top, 14)
                Spacer()
            }
        }
        .sheet(isPresented: $rulesPresented) {
            RulesBookletView()
                .environmentObject(assets)
        }
        .sheet(isPresented: $historyPresented) {
            GameHistoryView()
        }
        .overlay {
            if shouldShowVerdict {
                VerdictView(onDismiss: { appState.verdictDismissed = true })
                    .environmentObject(appState)
                    .environmentObject(appState.settings)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .overlay {
            if appState.handoffPending, let p = appState.session?.players.first(where: { $0.seat == appState.session?.currentSeat }) {
                HotSeatHandoffView(
                    playerName: p.name,
                    onContinue: { appState.handoffPending = false }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: shouldShowVerdict)
        .animation(.easeInOut(duration: 0.2),  value: appState.handoffPending)
    }

    private var shouldShowVerdict: Bool {
        guard let s = appState.session else { return false }
        return s.outcome != .inProgress && !appState.verdictDismissed
    }
}

private struct DeskBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.18, green: 0.13, blue: 0.10),
                     Color(red: 0.10, green: 0.07, blue: 0.05)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private struct BriefingStrip: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            if let s = appState.session {
                pill("PLAYER", s.players.first(where: { $0.seat == s.currentSeat })?.name ?? "—")
                pill("DIFFICULTY", s.difficulty.displayName)
                pill("PQ THIS TURN", "\(s.privateQuestionsAskedThisTurn)/\(s.difficulty.privateQuestionsPerTurn)")
                pill("OUTCOME", s.outcome.rawValue)
            } else {
                Text("No game in progress — press ON on the console.")
                    .font(.caption).italic()
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Text(AppVersion.display)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.35)))
    }

    private func pill(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption2).bold()
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(.white.opacity(0.08)))
    }
}
