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
    /// Headless mode: the CLI launches us with `--stage-agent` to stage the nightly purge manifest
    /// into the "To Delete" album, then quit. No window, no Dock icon — pure background work.
    static let isStageAgent = CommandLine.arguments.contains("--stage-agent")

    func applicationWillFinishLaunching(_ notification: Notification) {
        if Self.isStageAgent {
            // Run as a background agent: no Dock icon, no window ever shown.
            NSApp.setActivationPolicy(.prohibited)
            return
        }
        // Runs BEFORE the first WindowGroup window materializes.
        WindowStateGuard.applyOnLaunch(appName: "PurpleAttic", resetVersion: 1)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Self.isStageAgent else { return }
        // Close the WindowGroup window SwiftUI created (it never displayed under .prohibited),
        // do the staging, then terminate explicitly once it finishes.
        NSApp.windows.forEach { $0.close() }
        StagingAgent.run {
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // In stage-agent mode we close the window immediately but must NOT quit until staging is
        // done — termination is driven explicitly by StagingAgent's completion above.
        !Self.isStageAgent
    }
}
