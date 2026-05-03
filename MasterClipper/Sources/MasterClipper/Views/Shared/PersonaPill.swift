import SwiftUI

/// Cutesy persona badge — gradient capsule with a heart icon and the persona
/// code in bold white. Reused across the Clips list, Editing Queue, dashboard
/// rows, and anywhere else a clip's persona needs to "light up".
struct PersonaPill: View {
    @EnvironmentObject private var appState: AppState
    let code: String

    var body: some View {
        let color = appState.color(forPersona: code)
        return HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .font(.system(size: 9, weight: .bold))
            Text(code)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(
            LinearGradient(
                colors: [color.opacity(0.95), color.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule(style: .continuous)
        )
        .shadow(color: color.opacity(0.45), radius: 2, x: 0, y: 1)
    }
}
