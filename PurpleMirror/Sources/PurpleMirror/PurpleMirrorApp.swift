import SwiftUI

@main
struct PurpleMirrorApp: App {
    @StateObject private var controller = SyncController()
    @StateObject private var updater = UpdaterViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: controller, updater: updater)
        } label: {
            Image(systemName: controller.menuBarSymbol)
                .accessibilityLabel("PurpleMirror sync status")
        }
        .menuBarExtraStyle(.window)   // rich popover panel, not a plain menu

        Settings {
            SettingsView(controller: controller)
        }

        Window("PurpleMirror — Sync Log", id: "log") {
            LogView(controller: controller)
        }
        .defaultSize(width: 760, height: 480)
    }
}
