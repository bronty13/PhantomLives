import SwiftUI

@main
struct IrcleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var model: IrcleModel

    init() {
        let store = SettingsStore()
        _settingsStore = StateObject(wrappedValue: store)
        _model = StateObject(wrappedValue: IrcleModel(settingsStore: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(settingsStore)
        }
        .defaultSize(width: 940, height: 620)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Connect") { model.connectDefault() }
                    .keyboardShortcut("k", modifiers: [.command])
                Button("Disconnect") { model.disconnect() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(settingsStore)
        }
    }
}
