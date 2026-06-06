import AppKit

/// Wires the two launch-time PhantomLives standards: the window-state guard
/// (before SwiftUI materializes a window) and auto-backup-on-launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the App so the backup can read settings. Created early in the App
    /// init, assigned here.
    static var settingsStore: SettingsStore?

    func applicationWillFinishLaunching(_ notification: Notification) {
        WindowStateGuard.applyOnLaunch(appName: "PurpleArchive", resetVersion: 1)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let store = Self.settingsStore {
            BackupService.runOnLaunchIfDue(settingsStore: store)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
