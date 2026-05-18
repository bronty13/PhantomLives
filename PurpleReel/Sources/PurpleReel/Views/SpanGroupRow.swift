import SwiftUI

/// Sidebar row for a detected camera-card span (Kyno-parity row 29).
/// Shows the span's display label, segment count, and total
/// duration. Tap reveals the segments in the main browser;
/// right-click → "Combine Segments…" opens the existing
/// `CombineClipsSheet` pre-populated.
struct SpanGroupRow: View {
    @EnvironmentObject var appState: AppState
    let group: SpanDetectionService.SpanGroup

    var body: some View {
        Button {
            appState.revealSpanGroup(group)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.split.3x1")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.label)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(durationLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Reveal Segments") {
                appState.revealSpanGroup(group)
            }
            Button("Combine Segments…") {
                appState.combineSpanGroup(group)
            }
        }
    }

    private var durationLabel: String {
        let total = Int(group.totalDuration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        let dur = h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
        return "\(group.segments.count) seg · \(dur)"
    }
}
