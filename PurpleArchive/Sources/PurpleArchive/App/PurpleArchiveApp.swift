import SwiftUI

@main
struct PurpleArchiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = SettingsStore()
    @StateObject private var model: AppModel

    init() {
        let store = SettingsStore()
        AppDelegate.settingsStore = store
        _settings = StateObject(wrappedValue: store)
        _model = StateObject(wrappedValue: AppModel(settings: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(settings)
                .frame(minWidth: 820, minHeight: 520)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Archive…") { openArchivePanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .windowArrangement) {
                Button("Reset Window State…") {
                    WindowStateGuard.forceReset(appName: "PurpleArchive", resetVersion: 1)
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }

    private func openArchivePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            model.open(url)
        }
    }
}
