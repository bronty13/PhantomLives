import SwiftUI

/// The blue gradient run strip from the Mission Control redesign. Houses
/// the primary Run/Cancel button, the stage caption, and a continuous
/// progress bar — all on a single horizontal line. Replaces the older
/// 5-segment ProgressBar (which is preserved as `RunProgressBar` for use
/// when a smaller, label-free indicator is needed elsewhere).
struct RunStrip: View {
    @Environment(\.missionTheme) private var t
    @EnvironmentObject private var runner: ExportRunner

    let canRun: Bool
    let runAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            primaryButton
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(stageCaption)
                        .font(MissionFont.sans(11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                    Spacer(minLength: 4)
                    if let trailing = stageTrailing {
                        Text(trailing)
                            .font(MissionFont.mono(10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                ContinuousProgressBar(progress: progressFraction,
                                      indeterminate: runner.isRunning && runner.stage == 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(colors: [t.runGradStart, t.runGradEnd],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: t.runGradStart.opacity(0.32), radius: 16, x: 0, y: 8)
    }

    // MARK: - Sub-bits

    @ViewBuilder
    private var primaryButton: some View {
        if runner.isRunning {
            Button(action: cancelAction) {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                    Text(runner.isCancelling ? "Cancelling…" : "Cancel")
                        .font(MissionFont.sans(13, weight: .semibold))
                }
                .foregroundStyle(t.runGradStart)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.95))
                )
            }
            .buttonStyle(.plain)
            .disabled(runner.isCancelling)
        } else {
            Button(action: runAction) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Run export")
                        .font(MissionFont.sans(13, weight: .semibold))
                    Text("⌘ ⏎")
                        .font(MissionFont.mono(10))
                        .opacity(0.55)
                }
                .foregroundStyle(t.runGradStart)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.95))
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!canRun)
            .opacity(canRun ? 1 : 0.55)
        }
    }

    private var stageCaption: String {
        if !runner.isRunning && runner.stage == 0 {
            return canRun
                ? "Ready when you are"
                : "Pick a contact to enable Run"
        }
        let labels = [
            "Resolving contact",
            "Finding chats",
            "Reading messages",
            "Writing attachments",
            "Done"
        ]
        let idx = max(0, min(runner.stage - 1, labels.count - 1))
        if runner.stage == 0 { return "Starting…" }
        return "Stage \(runner.stage) of 5 · \(labels[idx])"
    }

    private var stageTrailing: String? {
        if !runner.isRunning && runner.stage == 5 { return "Done" }
        if runner.isRunning && runner.stage > 0   { return "\(runner.stage)/5" }
        return nil
    }

    private var progressFraction: Double {
        // 0 stage → 0%, 5 → 100%. Smoothed slightly so the user sees motion
        // even while a stage is in flight.
        guard runner.stage > 0 else { return 0 }
        return Double(runner.stage) / 5.0
    }
}

/// Continuous percentage bar styled for the Mission Control run strip.
/// Sits on a translucent track inside the gradient pill; `indeterminate`
/// switches to a slow shimmer for stage 0 (process spawned, no marker
/// received yet).
struct ContinuousProgressBar: View {
    var progress: Double
    var indeterminate: Bool = false

    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.22))
                if indeterminate {
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: w * 0.30)
                        .offset(x: phase * (w - w * 0.30))
                        .animation(.easeInOut(duration: 1.2)
                                   .repeatForever(autoreverses: true),
                                   value: phase)
                        .onAppear { phase = 1 }
                } else {
                    Capsule()
                        .fill(.white.opacity(0.95))
                        .frame(width: max(0, min(w, w * progress)))
                        .animation(.easeOut(duration: 0.35), value: progress)
                }
            }
        }
        .frame(height: 6)
    }
}
