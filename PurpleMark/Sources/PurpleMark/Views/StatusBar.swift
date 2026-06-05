import SwiftUI

/// Bottom status bar: live word / character / line counts and reading time,
/// matching the OpenMark screenshots (`342 words · 2191 characters · 43 lines ·
/// 2 min read`).
struct StatusBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let s = state.stats
        HStack(spacing: 6) {
            Text(parts(s))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if state.isDirty {
                Text("Edited")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(height: 24)
    }

    private func parts(_ s: DocStats) -> String {
        var pieces = [
            "\(s.words) " + (s.words == 1 ? "word" : "words"),
            "\(s.characters) characters",
            "\(s.lines) " + (s.lines == 1 ? "line" : "lines"),
        ]
        if s.readMinutes > 0 { pieces.append("\(s.readMinutes) min read") }
        return pieces.joined(separator: " · ")
    }
}
