import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        Form {
            Toggle("Enable autocorrect in markdown editors",
                   isOn: Binding(
                    get: { settingsStore.settings.autocorrectEnabled },
                    set: {
                        var s = settingsStore.settings
                        s.autocorrectEnabled = $0
                        settingsStore.settings = s
                        settingsStore.save()
                    }
                   ))
            HStack {
                Text("Default export directory")
                TextField("(default: ~/Downloads/PurpleTracker/Exports)", text: Binding(
                    get: { settingsStore.settings.defaultExportDirectory },
                    set: {
                        var s = settingsStore.settings
                        s.defaultExportDirectory = $0
                        settingsStore.settings = s
                        settingsStore.save()
                    }
                ))
                .textFieldStyle(.roundedBorder)
                Button("Choose…") { pickDir() }
            }
            Text("Resolved: \(settingsStore.resolvedExportDirectory.path)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            Divider()
            HStack {
                Text("Version: \(AppVersion.display)").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func pickDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            var s = settingsStore.settings
            s.defaultExportDirectory = url.path
            settingsStore.settings = s
            settingsStore.save()
        }
    }
}
