import SwiftUI

/// Small preview swatch that hints at the theme's gradient + accent. Used in
/// the Themes settings tab as a clickable picker.
struct ThemePreviewCard: View {
    let theme: Theme
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                LinearGradient(
                    colors: theme.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Circle().fill(theme.accentColor).frame(width: 8, height: 8)
                        Capsule().fill(.white.opacity(0.6)).frame(width: 40, height: 4)
                    }
                    Capsule().fill(theme.timelineTrackColor).frame(height: 2)
                    HStack(spacing: 4) {
                        Circle().fill(.orange).frame(width: 6, height: 6)
                        Circle().fill(.pink).frame(width: 6, height: 6)
                        Circle().fill(.green).frame(width: 6, height: 6)
                    }
                }
                .padding(10)
            }
            .frame(width: 120, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? theme.accentColor : Color.secondary.opacity(0.3),
                            lineWidth: isSelected ? 2 : 1)
            )

            Text(theme.name)
                .font(.caption)
                .fontWeight(isSelected ? .bold : .regular)
        }
    }
}
