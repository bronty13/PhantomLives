import SwiftUI

/// Vertical playback level meter — a classic mixing-desk bar that fills
/// green → yellow → red from the bottom, with a peak-hold tick that
/// falls back over time. Driven by `AudioPlayer.meterLevel` / `meterPeak`
/// for whichever stream is currently audible.
///
/// `active` dims the whole meter when this isn't the stream being
/// played (the detail pane shows an "in" and an "out" meter; only the
/// one matching the A/B selection animates).
struct LevelMeter: View {
    /// Normalized 0…1 fill height.
    var level: Float
    /// Normalized 0…1 peak-hold position.
    var peak: Float
    var label: String
    var active: Bool = true

    private let width: CGFloat = 10

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let h = proxy.size.height
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))

                    // Level fill.
                    Capsule()
                        .fill(meterGradient)
                        .frame(height: max(0, CGFloat(active ? level : 0) * h))

                    // Peak-hold tick.
                    if active && peak > 0.01 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.8))
                            .frame(height: 1.5)
                            .offset(y: -CGFloat(min(peak, 1)) * h + 0.75)
                    }
                }
            }
            .frame(width: width)
            .clipShape(Capsule())

            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .opacity(active ? 1 : 0.4)
        .help("\(label == "in" ? "Input" : "Output") level")
    }

    private var meterGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .green, location: 0.0),
                .init(color: .green, location: 0.6),
                .init(color: .yellow, location: 0.82),
                .init(color: .red, location: 1.0),
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}
