import SwiftUI
import AppKit

struct TranscodeQueueView: View {
    @ObservedObject var queue: TranscodeQueue
    /// C6 — the view runs in a stand-alone `Window` scene now, not
    /// a `.sheet`. SwiftUI's `dismissWindow` action closes the
    /// window cleanly without affecting any other open windows.
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Transcode Queue").font(.title3.bold())
                Spacer()
                Button("Open Output Folder") {
                    if let dir = try? TranscodeService.defaultOutputDirectory() {
                        NSWorkspace.shared.open(dir)
                    }
                }
                Button("Close") { dismissWindow(id: "transcode-queue") }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)

            Divider()

            List {
                if let cur = queue.current {
                    Section("Running") { row(cur) }
                }
                if !queue.pending.isEmpty {
                    Section("Pending") {
                        ForEach(queue.pending) { row($0) }
                    }
                }
                if !queue.done.isEmpty {
                    Section("Completed") {
                        ForEach(queue.done.reversed()) { row($0) }
                    }
                }
                if queue.current == nil && queue.pending.isEmpty && queue.done.isEmpty {
                    Text("No jobs yet. Pick a clip and choose Transcode → Preset.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Spacer()
                Button("Cancel All") { queue.cancelAll() }
                    .disabled(queue.pending.isEmpty && queue.current == nil)
            }
            .padding(12)
        }
        .frame(minWidth: 560, minHeight: 360)
    }

    @ViewBuilder
    private func row(_ job: TranscodeJob) -> some View {
        JobRow(job: job)
    }
}

private struct JobRow: View {
    @ObservedObject var job: TranscodeJob

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.source.lastPathComponent)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(job.preset.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                stateLabel
                if case .running = job.state {
                    ProgressView(value: job.progress, total: 1)
                        .progressViewStyle(.linear)
                }
                Spacer()
                if case .finished(let url) = job.state {
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
                if case .running = job.state {
                    Button("Cancel") { job.cancel() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch job.state {
        case .queued:
            Label("Queued", systemImage: "clock")
                .font(.caption).foregroundStyle(.secondary)
        case .running:
            Label(String(format: "%.0f%%", job.progress * 100),
                   systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
        case .finished:
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.octagon.fill")
                .font(.caption).foregroundStyle(.red)
                .lineLimit(2)
        case .cancelled:
            Label("Cancelled", systemImage: "stop.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
