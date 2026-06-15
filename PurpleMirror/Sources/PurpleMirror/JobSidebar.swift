import SwiftUI

/// Shared fixed-width sidebar listing every managed job **grouped by source**, with the current
/// selection bound to `model.selectedJobID`. Used by both the Settings window and the Logs window
/// so they navigate identically (the PhantomLives manual-`HStack` pattern — not `NavigationSplitView`).
struct JobSidebar: View {
    @ObservedObject var model: JobsModel
    var width: CGFloat = 210

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.groups, id: \.name) { grp in
                    VStack(alignment: .leading, spacing: 2) {
                        header(grp.name, jobs: grp.jobs)
                        ForEach(grp.jobs) { row($0) }
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .frame(width: width)
        .background(.ultraThinMaterial)
    }

    private func header(_ name: String, jobs: [JobController]) -> some View {
        let health = model.groupHealth(jobs)
        return HStack(spacing: 5) {
            Text(name.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Image(systemName: health.symbol)
                .font(.caption2)
                .foregroundStyle(health.color)
            Spacer()
            Text("\(jobs.count)").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
    }

    private func row(_ job: JobController) -> some View {
        Button {
            model.selectedJobID = job.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: job.health.symbol)
                    .foregroundStyle(job.health.color)
                    .font(.caption)
                    .frame(width: 16)
                Text(job.shortName).lineLimit(1)
                Spacer(minLength: 0)
                if job.isRunning { ProgressView().controlSize(.mini) }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(model.selectedJobID == job.id ? Color.accentColor.opacity(0.22) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}
