import AppKit

/// Hooks into AppKit's launch lifecycle BEFORE SwiftUI materializes the first
/// window — the earliest point at which we can sanitize persisted window/split
/// state. See `WindowStateGuard`.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Bump when shipping a layout change that should invalidate every user's
    /// persisted window state. Each user's next launch fires a one-shot wipe.
    static let windowResetVersion = 1

    func applicationWillFinishLaunching(_ notification: Notification) {
        WindowStateGuard.applyOnLaunch(
            appName: "PurpleDiary",
            resetVersion: Self.windowResetVersion
        )
    }
}
