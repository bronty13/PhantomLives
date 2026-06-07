import AppKit

/// Hooks into AppKit's launch lifecycle BEFORE SwiftUI materializes the
/// first window — the earliest point at which we can sanitize persisted
/// window/split state (see `WindowStateGuard`).
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Bump when shipping a layout change that should invalidate every
    /// user's persisted window state. The next launch for each user fires
    /// a one-shot wipe, then increments their stored version.
    static let windowResetVersion = 1

    func applicationWillFinishLaunching(_ notification: Notification) {
        WindowStateGuard.applyOnLaunch(
            appName: "PurpleSpeak",
            resetVersion: Self.windowResetVersion
        )
    }
}
