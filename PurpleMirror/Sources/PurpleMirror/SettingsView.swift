import SwiftUI

/// Settings window. A fixed-width sidebar lists every managed job **grouped by source**
/// (the PhantomLives manual-`HStack` pattern — not `NavigationSplitView`), with the selected
/// job's schedule + locations on the right. This replaces the old segmented "tabs across the
/// top" picker, which became unreadable once a dozen+ jobs were managed.
struct SettingsView: View {
    @ObservedObject var model: JobsModel
    private let sidebarWidth: CGFloat = 210

    var body: some View {
        TabView {
            jobsTab
                .tabItem { Label("Jobs", systemImage: "list.bullet") }
            HostsSettingsView(model: model)
                .tabItem { Label("Hosts", systemImage: "network") }
        }
        .frame(width: 680, height: 560)
        .task { await model.refreshAll() }
    }

    @ViewBuilder
    private var jobsTab: some View {
        if model.jobs.isEmpty {
            ContentUnavailableView(
                "No managed jobs",
                systemImage: "gearshape",
                description: Text("PurpleMirror manages PhantomLives launchd agents in ~/Library/LaunchAgents — locally and on any hosts added under the Hosts tab.")
            )
        } else {
            HStack(spacing: 0) {
                JobSidebar(model: model, width: sidebarWidth)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
                if !job.canEditSchedule {
                    Text("On \(job.hostName) — schedule editing is coming soon. Run Now works now.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Automatic background run", isOn: Binding(
                    get: { job.agentLoaded },
                    set: { $0 ? job.enable() : job.disable() }
                ))
                .help("Loads/unloads the launchd agent that runs this job on a fixed interval.")
                .disabled(!job.canEditSchedule)

                Picker("Run every", selection: $selection) {
                    ForEach(presets, id: \.1) { Text($0.0).tag($0.1) }
                    Text("Custom…").tag(-1)
                }
                .disabled(!job.agentLoaded || !job.canEditSchedule)
                .onChange(of: selection) { _, new in
                    isCustom = (new == -1)
                    if new != -1 { job.setInterval(new) }
                }

                if isCustom {
                    Stepper(value: $customMinutes, in: 5...1440, step: 5) {
                        Text("Every \(customMinutes) minutes")
                    }
                    Button("Apply custom interval") { job.setInterval(customMinutes * 60) }
                        .disabled(!job.agentLoaded || !job.canEditSchedule)
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
                LabeledContent("Host") {
                    Text(job.hostName).foregroundStyle(.secondary)
                }
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
