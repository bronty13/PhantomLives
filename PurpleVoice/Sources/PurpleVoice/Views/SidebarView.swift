import SwiftUI

/// Queue listing in the sidebar. Each row shows the clip's filename, a
/// status icon, and (during processing) an inline progress bar. Tapping
/// a row selects it for the detail pane; the disclosure chevron on
/// `done` rows reveals the file in Finder.
struct SidebarView: View {
    @EnvironmentObject var queue: ProcessingQueue

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Queue")
                    .font(.headline)
                Spacer()
                if queue.clips.contains(where: { $0.status == .done }) {
                    Button("Clear done") {
                        queue.clearCompleted()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()
            if queue.clips.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                queueList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("No clips yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Drop audio or video into the main pane.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
    }

    private var queueList: some View {
        List(selection: Binding(
            get: { queue.selectedClipID },
            set: { queue.selectedClipID = $0 }
        )) {
            ForEach(queue.clips) { clip in
                SidebarRow(clip: clip)
                    .tag(Optional(clip.id))
                    .contextMenu {
                        if clip.status == .done, let out = clip.outputURL {
                            Button("Reveal Output in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([out])
                            }
                        }
                        Button("Reveal Source in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([clip.sourceURL])
                        }
                        Divider()
                        Button("Remove from Queue", role: .destructive) {
                            queue.remove(clip)
                        }
                    }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct SidebarRow: View {
    @ObservedObject var clip: Clip

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                statusIcon
                Text(clip.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if clip.status == .processing {
                ProgressView(value: clip.progress)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            } else if clip.status == .failed, let msg = clip.lastError {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch clip.status {
        case .queued:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .processing:
            Image(systemName: "waveform.circle")
                .foregroundStyle(.blue)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}
