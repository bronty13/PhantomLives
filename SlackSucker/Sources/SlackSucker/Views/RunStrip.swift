import SwiftUI

/// Blue-gradient Run / Cancel strip + indeterminate progress while a
/// run is in flight. Slackdump doesn't emit a deterministic percent so
/// the bar stays animated rather than tracking a step counter.
struct RunStrip: View {
    @Environment(\.appTheme) private var theme

    let isRunning: Bool
    let isCancelling: Bool
    let phase: String?
    var onRun: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button(action: onRun) {
                    HStack {
                        Image(systemName: "tray.and.arrow.down.fill")
                        Text(isRunning ? (isCancelling ? "Cancelling…" : "Running…") : "Run archive")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(colors: [theme.runGradStart, theme.runGradEnd],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isRunning)

                if isRunning {
                    Button("Cancel", role: .destructive, action: onCancel)
                        .disabled(isCancelling)
                }

                Spacer()

                if let phase, isRunning {
                    Text(phase)
                        .font(AppFont.sans(12))
                        .foregroundStyle(.secondary)
                }
            }
            if isRunning {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(theme.accent)
            }
        }
    }
}
