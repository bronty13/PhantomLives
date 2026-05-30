import SwiftUI

/// A 0–5 star mood picker. Tapping a star sets the rating; tapping the current
/// rating's last star again clears it back to `.unset`.
struct MoodStarsView: View {
    @Binding var mood: Mood
    var interactive: Bool = true
    var starSize: CGFloat = 16

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= mood.rawValue ? "star.fill" : "star")
                    .font(.system(size: starSize))
                    .foregroundStyle(value <= mood.rawValue ? Color.yellow : Color.secondary.opacity(0.5))
                    .onTapGesture {
                        guard interactive else { return }
                        if mood.rawValue == value {
                            mood = .unset
                        } else {
                            mood = Mood(rawValue: value) ?? .unset
                        }
                    }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Mood")
        .accessibilityValue(mood.label)
    }
}
