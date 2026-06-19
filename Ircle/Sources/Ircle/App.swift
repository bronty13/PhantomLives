import SwiftUI

@main
struct IrcleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var model: IrcleModel
    @StateObject private var facesStore: FacesStore

    init() {
        let store = SettingsStore()
        _settingsStore = StateObject(wrappedValue: store)
        _model = StateObject(wrappedValue: IrcleModel(settingsStore: store))
        _facesStore = StateObject(wrappedValue: FacesStore(baseDir: SettingsStore.supportDirectory))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(settingsStore)
                .environmentObject(facesStore)
        }
        .defaultSize(width: 940, height: 620)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Connect") { model.connectDefault() }
                    .keyboardShortcut("k", modifiers: [.command])
                Button("Disconnect") { model.disconnectSelected() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                FacesMenuItem()
            }
            CommandMenu("Servers") {
                ForEach(settingsStore.settings.servers) { profile in
                    Button("Connect to \(profile.name)") { model.connect(to: profile) }
                }
                Divider()
                Button("Disconnect Current") { model.disconnectSelected() }
            }
        }

        // The Faces window — a separate window like classic Ircle. Single
        // instance, opened via `openWindow(id: "faces")`.
        Window("Faces", id: "faces") {
            FacesView()
                .environmentObject(model)
                .environmentObject(settingsStore)
                .environmentObject(facesStore)
        }
        .defaultSize(width: 420, height: 480)

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(settingsStore)
        }
    }
}

/// Menu item that opens the Faces window. Lives in a View so it can read the
/// `openWindow` environment action (not available directly in `App`).
private struct FacesMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Faces") { openWindow(id: "faces") }
            .keyboardShortcut("f", modifiers: [.command, .shift])
    }
}
