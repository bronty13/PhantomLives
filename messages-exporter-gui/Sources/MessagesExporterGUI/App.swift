import SwiftUI

@main
struct MessagesExporterGUIApp: App {
    @StateObject private var runner   = ExportRunner()
    @StateObject private var contacts = ContactsService()

    var body: some Scene {
        WindowGroup("Messages Exporter") {
            RootView()
                .environmentObject(runner)
                .environmentObject(contacts)
                .frame(minWidth: 640, minHeight: 560)
                .onAppear {
                    contacts.requestAccessIfNeeded()
                }
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
