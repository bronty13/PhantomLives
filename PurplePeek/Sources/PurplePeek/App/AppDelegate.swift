import AppKit

/// Runs the WindowStateGuard before SwiftUI materializes its first window, and quits the
/// app when the last window closes (standard single-window-document feel).
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Bump to invalidate every install's persisted window state on next launch.
    static let windowResetVersion = 1

    func applicationWillFinishLaunching(_ notification: Notification) {
        WindowStateGuard.applyOnLaunch(appName: "PurplePeek", resetVersion: Self.windowResetVersion)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
