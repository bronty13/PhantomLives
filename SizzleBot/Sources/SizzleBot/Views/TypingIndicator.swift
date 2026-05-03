import SwiftUI

struct TypingIndicator: View {
    let character: Character
    @State private var animating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text(character.avatar)
                .font(.system(size: 16))
                .frame(width: 30, height: 30)
                .background(character.color.opacity(0.15))
                .clipShape(Circle())

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(character.color)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animating ? 1.25 : 0.75)
                        .opacity(animating ? 1.0 : 0.4)
                        .animation(
                            .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.18),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer(minLength: 60)
        }
        .onAppear { animating = true }
    }
}
