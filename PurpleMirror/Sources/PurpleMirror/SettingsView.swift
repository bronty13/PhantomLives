import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: JobsModel

    var body: some View {
        VStack(spacing: 0) {
            if model.jobs.isEmpty {
                ContentUnavailableView(
                    "No managed jobs",
                    systemImage: "gearshape",
                    description: Text("PurpleMirror manages PhantomLives launchd agents in ~/Library/LaunchAgents.")
                )
            } else {
                Picker("Job", selection: Binding(
                    get: { model.selectedJobID ?? model.jobs.first?.id },
                    set: { model.selectedJobID = $0 }
                )) {
                    ForEach(model.jobs) { Text($0.displayName).tag(Optional($0.id)) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding([.horizontal, .top])

                if let job = model.selectedJob {
                    JobSettingsForm(job: job)
                        .id(job.id)   // fresh @State per job
                }
            }
        }
        .frame(width: 500, height: 480)
        .task { await model.refreshAll() }
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
