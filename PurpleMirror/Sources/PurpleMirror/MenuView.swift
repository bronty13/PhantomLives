import SwiftUI

/// The popover panel shown when the menu-bar icon is clicked: a row per managed
/// background job, plus app-wide actions.
struct MenuView: View {
    @ObservedObject var model: JobsModel
    @ObservedObject var updater: UpdaterViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if model.jobs.isEmpty {
                Text("No managed jobs found.\nPurpleMirror watches PhantomLives launchd agents in ~/Library/LaunchAgents.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(model.groups, id: \.name) { grp in
                            GroupSection(name: grp.name, jobs: grp.jobs,
                                         health: model.groupHealth(grp.jobs),
                                         openLog: { openLog(for: $0) })
                        }
                    }
                }
                // A `.window` MenuBarExtra sizes to content's *ideal* height, but a
                // bare ScrollView reports ~0 there and collapses to an empty strip.
                // Give it a DEFINITE height sized to the rows (capped) so it renders
                // and only scrolls once the list is genuinely tall.
                .frame(height: listHeight)
            }
            Divider()
            actions
        }
        .padding(14)
        .frame(width: 360)
        .task { await model.refreshAll() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.aggregateHealth.symbol)
                .font(.title2)
                .foregroundStyle(healthColor(model.aggregateHealth))
            VStack(alignment: .leading, spacing: 1) {
                Text("PurpleMirror").font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.jobs.contains(where: { $0.isRunning }) { ProgressView().controlSize(.small) }
        }
    }

    private var subtitle: String {
        let n = model.jobs.count
        return n == 0 ? "No jobs" : "\(n) job\(n == 1 ? "" : "s") · \(model.aggregateHealth.label)"
    }

    /// Estimated natural height of the grouped job list, capped so very long lists
    /// scroll instead of growing the window past ~460pt.
    private var listHeight: CGFloat {
        let rows = CGFloat(model.jobs.count) * 44      // each JobRow ≈ 44pt
        let headers = CGFloat(model.groups.count) * 34 // each group header ≈ 34pt
        return min(rows + headers + 12, 460)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    openLog(for: model.selectedJobID ?? model.jobs.first?.id)
                } label: {
                    Label("Open Logs…", systemImage: "doc.plaintext").frame(maxWidth: .infinity)
                }
                SettingsLink {
                    Label("Settings", systemImage: "gearshape").frame(maxWidth: .infinity)
                }
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            }

            Button {
                updater.checkForUpdates()
            } label: {
                Label("Check for Updates…", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
            }
            .disabled(!updater.canCheckForUpdates)

            HStack {
                Text("v\(updater.appVersion)").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button(role: .destructive) { NSApplication.shared.terminate(nil) } label: { Text("Quit") }
                    .buttonStyle(.borderless).font(.caption)
            }
            .padding(.top, 2)
        }
    }

    private func openLog(for id: String?) {
        if let id { model.selectedJobID = id }
        openWindow(id: "log")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func healthColor(_ h: SyncStatusParser.Health) -> Color {
        switch h {
        case .healthy: return .green
        case .running: return .accentColor
        case .warning: return .orange
        case .error:   return .red
        }
    }
}

/// A collapsible section grouping one source's jobs (e.g. all of "Rachel").
private struct GroupSection: View {
    let name: String
    let jobs: [JobController]
    let health: SyncStatusParser.Health
    var openLog: (String) -> Void
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary)
                    Image(systemName: health.symbol).foregroundStyle(color(health)).font(.caption)
                    Text(name).font(.subheadline.weight(.semibold))
                    Text("\(jobs.count)").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            if expanded {
                VStack(spacing: 6) {
                    ForEach(jobs) { job in JobRow(job: job) { openLog(job.id) } }
                }
                .padding(.leading, 4)
            }
        }
    }

    private func color(_ h: SyncStatusParser.Health) -> Color {
        switch h {
        case .healthy: return .green
        case .running: return .accentColor
        case .warning: return .orange
        case .error:   return .red
        }
    }
}

/// One job's row: status glyph, name, last-activity digest, and a Run-Now / View-Log pair.
private struct JobRow: View {
    @ObservedObject var job: JobController
    var onViewLog: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: job.health.symbol)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(job.shortName).font(.callout.weight(.medium))
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if job.isRunning {
                ProgressView().controlSize(.small)
            } else {
                Button { job.runNow() } label: { Image(systemName: "play.circle") }
                    .buttonStyle(.borderless)
                    .help("Run \(job.displayName) now")
            }
            Button(action: onViewLog) { Image(systemName: "doc.plaintext") }
                .buttonStyle(.borderless)
                .help("View \(job.displayName) log")
        }
    }

    private var secondary: String {
        var parts: [String] = [job.lastActivityRelative]
        if let h = job.summary?.headline { parts.append(h) }
        else { parts.append(job.agentLoaded ? "Auto every \(job.intervalHuman)" : "Auto-run off") }
        return parts.joined(separator: " · ")
    }

    private var color: Color {
        switch job.health {
        case .healthy: return .green
        case .running: return .accentColor
        case .warning: return .orange
        case .error:   return .red
        }
    }
}
