import SwiftUI

@main
struct MessagesExporterGUIApp: App {
    @StateObject private var runner = ExportRunner()

    var body: some Scene {
        WindowGroup("Messages Exporter") {
            RootView()
                .environmentObject(runner)
                .frame(minWidth: 640, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
        }
    }
}
