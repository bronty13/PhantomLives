import SwiftUI

@main
struct MessagesExporterGUIApp: App {
    @StateObject private var runner = ExportRunner()

    var body: some Scene {
        WindowGroup("Messages Exporter") {
            RootView()
                .environmentObject(runner)
                // Min size keeps the four-tile row + form card on screen
                // without horizontal scrolling. Ideal matches the design's
                // 1100×780 artboard so a fresh launch hits the intended
                // proportions.
                .frame(minWidth: 920, idealWidth: 1100,
                       minHeight: 640, idealHeight: 780)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
        }
    }
}
