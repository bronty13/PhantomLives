import SwiftUI

@main
struct PurpleVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var queue = ProcessingQueue()
    @StateObject private var settings = SettingsStore()
    @StateObject private var presetStore = PresetStore()

    var body: some Scene {
        WindowGroup("PurpleVoice") {
            ContentView()
                .environmentObject(queue)
                .environmentObject(settings)
                .environmentObject(presetStore)
                .frame(minWidth: 720, minHeight: 460)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Clips…") {
                    NotificationCenter.default.post(name: .pvAddClipsRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
            CommandGroup(after: .windowArrangement) {
                Button("Reset Window State…") {
                    WindowStateGuard.forceReset(appName: "PurpleVoice",
                                                resetVersion: AppDelegate.windowResetVersion)
                    let alert = NSAlert()
                    alert.messageText = "Window state reset."
                    alert.informativeText = "Quit and relaunch PurpleVoice for the change to take effect."
                    alert.runModal()
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(presetStore)
                .frame(width: 480)
        }
    }
}

extension Notification.Name {
    static let pvAddClipsRequested = Notification.Name("pvAddClipsRequested")
}
