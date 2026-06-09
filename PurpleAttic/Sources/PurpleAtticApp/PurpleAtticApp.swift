import SwiftUI
import AppKit

@main
struct PurpleAtticApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 920, minHeight: 620)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Reset Window State…") {
                    WindowStateGuard.forceReset(appName: "PurpleAttic", resetVersion: 1)
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Runs BEFORE the first WindowGroup window materializes.
        WindowStateGuard.applyOnLaunch(appName: "PurpleAttic", resetVersion: 1)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
