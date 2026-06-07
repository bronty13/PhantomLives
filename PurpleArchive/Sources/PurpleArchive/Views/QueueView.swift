import SwiftUI

/// The batch panel: every queued/running/finished extract or compress, with
/// per-job progress, cancel, reveal, and a concurrency control.
struct QueueView: View {
    @EnvironmentObject var queue: JobQueue

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            if queue.jobs.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(queue.jobs) { job in JobRow(job: job) }
                }
                .listStyle(.inset)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up").foregroundStyle(.purple)
            Text("Queue").font(.headline)
            if queue.activeCount > 0 {
                Text("\(queue.activeCount) active").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Text("Parallel").font(.caption).foregroundStyle(.secondary)
                Stepper("\(queue.maxConcurrent)", value: $queue.maxConcurrent, in: 1...16)
                    .labelsHidden()
                Text("\(queue.maxConcurrent)").font(.caption).monospacedDigit().frame(width: 18)
            }
            Button("Clear Finished") { queue.clearFinished() }
                .disabled(!queue.jobs.contains { [.done, .failed, .cancelled].contains($0.status) })
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 46)).foregroundStyle(.purple.opacity(0.45))
            Text("No jobs running").font(.title3)
            Text("Drop several archives to extract them all at once, across your cores.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct JobRow: View {
    let job: QueueJob
    @EnvironmentObject var queue: JobQueue

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: job.systemImage).foregroundStyle(.purple).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.title).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    statusBadge
                    if !job.detail.isEmpty {
                        Text(job.detail).font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                if job.status == .running {
                    if let p = job.progress { ProgressView(value: p) }
                    else { ProgressView().progressViewStyle(.linear) }
                }
            }
            Spacer()
            trailing
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder private var statusBadge: some View {
        switch job.status {
        case .queued:    label("Queued", "clock", .secondary)
        case .running:   label("Running", "bolt.fill", .purple)
        case .done:      label("Done", "checkmark.circle.fill", .green)
        case .failed:    label("Failed", "xmark.octagon.fill", .red)
        case .cancelled: label("Cancelled", "minus.circle", .secondary)
        }
    }

    private func label(_ t: String, _ icon: String, _ color: Color) -> some View {
        Label(t, systemImage: icon).font(.caption2).foregroundStyle(color)
    }

    @ViewBuilder private var trailing: some View {
        switch job.status {
        case .queued, .running:
            Button { queue.cancel(job.id) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        case .done:
            if let url = job.resultURL {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                    Image(systemName: "magnifyingglass.circle")
                }.buttonStyle(.plain).foregroundStyle(.purple)
            }
        default: EmptyView()
        }
    }
}
