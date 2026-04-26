import SwiftUI

/// Shows the CLI's [N/5] pipeline as a 5-step bar. Stage 0 = idle,
/// 1...5 are the CLI's published markers. Bar fills proportionally and
/// labels the current stage so the user knows what the script is doing.
struct ProgressBar: View {
    let stage: Int
    let isRunning: Bool

    private let stageLabels = [
        "Resolve contact",
        "Find chats",
        "Read messages",
        "Write attachments",
        "Done"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(i < stage ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(height: 8)
                }
            }
            HStack {
                Text(currentStageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private var currentStageText: String {
        if stage == 0 { return "Idle" }
        let idx = max(0, min(stage - 1, stageLabels.count - 1))
        return "\(stage)/5 — \(stageLabels[idx])"
    }
}
