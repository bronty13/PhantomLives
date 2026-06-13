import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: SyncController

    // Interval presets (seconds). "Custom" reveals a stepper.
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
                Toggle("Automatic background sync", isOn: Binding(
                    get: { controller.agentLoaded },
                    set: { $0 ? controller.enableAutoSync() : controller.disableAutoSync() }
                ))
                .help("Installs a launchd agent that mirrors on a fixed interval and at login.")

                Picker("Sync every", selection: $selection) {
                    ForEach(presets, id: \.1) { Text($0.0).tag($0.1) }
                    Text("Custom…").tag(-1)
                }
                .disabled(!controller.agentLoaded)
                .onChange(of: selection) { _, new in
                    isCustom = (new == -1)
                    if new != -1 { controller.setInterval(new) }
                }

                if isCustom {
                    Stepper(value: $customMinutes, in: 5...1440, step: 5) {
                        Text("Every \(customMinutes) minutes")
                    }
                    Button("Apply custom interval") {
                        controller.setInterval(customMinutes * 60)
                    }
                    .disabled(!controller.agentLoaded)
                }
            }

            Section("Run") {
                Button {
                    controller.syncNow()
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(controller.isSyncing)
                if let msg = controller.lastActionMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Locations") {
                LabeledContent("Target vault") {
                    Text(controller.vaultPath.isEmpty ? "—" : controller.vaultPath)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.middle)
                }
                LabeledContent("Sync script") {
                    HStack {
                        TextField("", text: $controller.scriptPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Choose…") { chooseScript() }
                    }
                }
                Text("The vault is whatever the agent was installed with (baked into its plist). To change it, set OBSIDIAN_VAULT and reinstall per docs/obsidian-setup.md.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
        .task {
            await controller.refresh()
            // Sync the picker to the live interval if it matches a preset.
            if presets.contains(where: { $0.1 == controller.intervalSeconds }) {
                selection = controller.intervalSeconds
            } else {
                selection = -1; isCustom = true
                customMinutes = max(5, controller.intervalSeconds / 60)
            }
        }
    }

    private func chooseScript() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select sync-md-to-obsidian.sh"
        if panel.runModal() == .OK, let url = panel.url {
            controller.scriptPath = url.path
        }
    }
}
