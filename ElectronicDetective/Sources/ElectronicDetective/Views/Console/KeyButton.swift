import SwiftUI

/// One key on the console. Press/release animation, no audio in M1 — the
/// key-click sound arrives with `SoundBank` in M3.
struct KeyButton: View {
    enum Tint { case black, blue, red, gray }

    let label: String
    let tint: Tint
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: {
            withAnimation(.easeOut(duration: 0.06)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                withAnimation(.easeOut(duration: 0.10)) { pressed = false }
                action()
            }
        }) {
            Text(label)
                .font(.system(size: label.count > 2 ? 11 : 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(fillGradient)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.black.opacity(0.5), lineWidth: 1)
                        )
                        .scaleEffect(pressed ? 0.95 : 1.0)
                        .shadow(color: .black.opacity(pressed ? 0.2 : 0.5), radius: pressed ? 1 : 3, y: pressed ? 0 : 2)
                )
        }
        .buttonStyle(.plain)
    }

    private var fillGradient: LinearGradient {
        let (top, bottom): (Color, Color)
        switch tint {
        case .black: top = .init(white: 0.18); bottom = .init(white: 0.05)
        case .blue:  top = Color(red: 0.22, green: 0.35, blue: 0.62); bottom = Color(red: 0.10, green: 0.18, blue: 0.40)
        case .red:   top = Color(red: 0.78, green: 0.20, blue: 0.16); bottom = Color(red: 0.45, green: 0.08, blue: 0.06)
        case .gray:  top = .init(white: 0.50); bottom = .init(white: 0.30)
        }
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }
}
