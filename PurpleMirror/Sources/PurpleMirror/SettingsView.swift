import SwiftUI

/// Settings window. A fixed-width sidebar lists every managed job **grouped by source**
/// (the PhantomLives manual-`HStack` pattern — not `NavigationSplitView`), with the selected
/// job's schedule + locations on the right. This replaces the old segmented "tabs across the
/// top" picker, which became unreadable once a dozen+ jobs were managed.
struct SettingsView: View {
    @ObservedObject var model: JobsModel
    private let sidebarWidth: CGFloat = 210

    var body: some View {
        Group {
            if model.jobs.isEmpty {
                ContentUnavailableView(
                    "No managed jobs",
                    systemImage: "gearshape",
                    description: Text("PurpleMirror manages PhantomLives launchd agents in ~/Library/LaunchAgents.")
                )
            } else {
                HStack(spacing: 0) {
                    sidebar
                        .frame(width: sidebarWidth)
                        .background(.ultraThinMaterial)
                    Divider()
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 680, height: 520)
        .task { await model.refreshAll() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.groups, id: \.name) { grp in
                    VStack(alignment: .leading, spacing: 2) {
                        groupHeader(grp.name, jobs: grp.jobs)
                        ForEach(grp.jobs) { sidebarRow($0) }
                    }
                }
            }
            .padding(.vertical, 10)
        }
    }

    private func groupHeader(_ name: String, jobs: [JobController]) -> some View {
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

    private func sidebarRow(_ job: JobController) -> some View {
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

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let job = model.selectedJob {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: job.health.symbol)
                        .font(.title3)
                        .foregroundStyle(job.health.color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(job.displayName).font(.headline)
                        Text(job.health.label).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                Divider()
                JobSettingsForm(job: job)
                    .id(job.id)   // fresh @State per job
            }
        } else {
            ContentUnavailableView("Select a job", systemImage: "sidebar.left")
        }
    }
}

/// Schedule + locations for a single job.
private struct JobSettingsForm: View {
    @ObservedObject var job: JobController

    private let presets: [(String, Int)] = [
        ("15 minutes", 900), ("30 minutes", 1800),
        ("1 hour", 3600), ("2 hours", 7200), ("6 hours", 21600)
    ]
    @State private var selection: Int = 3600
    @State private var customMinutes: Int = 60
    @State private var isCustom = false

    var body: some View {
        Form {
            Section("Schedule") {
                Toggle("Automatic background run", isOn: Binding(
                    get: { job.agentLoaded },
                    set: { $0 ? job.enable() : job.disable() }
                ))
                .help("Loads/unloads the launchd agent that runs this job on a fixed interval.")

                Picker("Run every", selection: $selection) {
                    ForEach(presets, id: \.1) { Text($0.0).tag($0.1) }
                    Text("Custom…").tag(-1)
                }
                .disabled(!job.agentLoaded)
                .onChange(of: selection) { _, new in
                    isCustom = (new == -1)
                    if new != -1 { job.setInterval(new) }
                }

                if isCustom {
                    Stepper(value: $customMinutes, in: 5...1440, step: 5) {
                        Text("Every \(customMinutes) minutes")
                    }
                    Button("Apply custom interval") { job.setInterval(customMinutes * 60) }
                        .disabled(!job.agentLoaded)
                }
            }

            Section("Run") {
                Button {
                    job.runNow()
                } label: {
                    Label("Run Now", systemImage: "play.circle")
                }
                .disabled(job.isRunning)
                if let msg = job.lastActionMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Locations") {
                LabeledContent("Log") {
                    Text(job.logPath.isEmpty ? "—" : job.logPath)
                        .textSelection(.enabled).foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.middle)
                }
                if let script = job.scriptPath {
                    LabeledContent("Script") {
                        Text(script)
                            .textSelection(.enabled).foregroundStyle(.secondary)
                            .lineLimit(2).truncationMode(.middle)
                    }
                }
                LabeledContent("launchd label") {
                    Text(job.label).textSelection(.enabled).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { syncSelection() }
        .onChange(of: job.intervalSeconds) { _, _ in syncSelection() }
    }

    private func syncSelection() {
        if presets.contains(where: { $0.1 == job.intervalSeconds }) {
            selection = job.intervalSeconds
            isCustom = false
        } else {
            selection = -1
            isCustom = true
            customMinutes = max(5, job.intervalSeconds / 60)
        }
    }
}
