import SwiftUI
import PurpleDedupCore

/// Header strip for the comparison pane: cluster title + kind capsule + thumb-
/// size slider + per-cluster Trash button + Approve & Next.
struct ClusterHeader: View {
    let selection: ClusterSelection
    @Binding var thumbSize: CGFloat
    let pendingDeletes: [DiscoveredFile]
    let onApproveAndNext: () -> Void
    let onRequestTrash: ([DiscoveredFile]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(selection.title).font(.title3).bold()
                Spacer()
                Text(selection.kindLabel)
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(selection.kindColor.opacity(0.2))
                    .foregroundStyle(selection.kindColor)
                    .clipShape(Capsule())
            }
            Text(selection.subtitle).font(.callout).foregroundStyle(.secondary)
            HStack {
                Text("Thumbnail size").font(.caption).foregroundStyle(.secondary)
                Slider(value: $thumbSize, in: 96...360, step: 16).frame(maxWidth: 220)
                Text("\(Int(thumbSize))px").font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                if !pendingDeletes.isEmpty {
                    Button(role: .destructive) {
                        onRequestTrash(pendingDeletes)
                    } label: {
                        Label("Trash \(pendingDeletes.count) duplicate\(pendingDeletes.count == 1 ? "" : "s")", systemImage: "trash")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help("Move just this cluster's marked files to Trash (skips the cross-cluster batch)")
                }
                Button {
                    onApproveAndNext()
                } label: {
                    Label("Approve & next", systemImage: "checkmark.arrow.trianglehead.counterclockwise")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .help("Accept the current recommendation and jump to the next undecided cluster (⌘⏎)")
            }
        }
    }
}
