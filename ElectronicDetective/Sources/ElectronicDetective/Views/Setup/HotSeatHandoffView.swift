import SwiftUI

/// Full-window blackout shown when the seat changes in a 2+ player game.
/// Hides the previous player's notepad and rolodex notes until the next
/// player taps to continue. Mirrors the "pass the console" beat of the
/// original tabletop game.
struct HotSeatHandoffView: View {
    let playerName: String
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Text("PASS THE CONSOLE")
                    .font(.caption).bold().tracking(4)
                    .foregroundStyle(.white.opacity(0.55))
                Text(playerName)
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 12)
                Text("It's your turn. Tap anywhere when you're ready.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            .padding(48)
        }
        .contentShape(Rectangle())
        .onTapGesture { onContinue() }
    }
}
