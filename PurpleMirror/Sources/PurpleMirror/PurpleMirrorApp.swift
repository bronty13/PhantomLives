import SwiftUI

@main
struct PurpleMirrorApp: App {
    @StateObject private var model = JobsModel()
    @StateObject private var updater = UpdaterViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model, updater: updater)
        } label: {
            Image(systemName: model.aggregateHealth.symbol)
                .accessibilityLabel("PurpleMirror jobs status")
        }
        .menuBarExtraStyle(.window)   // rich popover panel, not a plain menu

        Settings {
            SettingsView(model: model)
        }

        Window("PurpleMirror — Job Logs", id: "log") {
            LogView(model: model)
        }
        .defaultSize(width: 940, height: 520)
    }
}
