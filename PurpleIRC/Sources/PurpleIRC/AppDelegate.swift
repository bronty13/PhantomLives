import AppKit

/// Hooks into AppKit's launch lifecycle BEFORE SwiftUI materializes the
/// first window. This is the earliest point at which we can sanitize
/// persisted window/split state — see `WindowStateGuard`.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Bump this integer when shipping a layout change that should
    /// invalidate every user's persisted window state. The next launch
    /// for each user fires a one-shot wipe (then increments their
    /// stored version so it doesn't run again).
    // v1 (2026-05-24): top-level sidebar migrated off NavigationSplitView
    //   onto a manual HStack with a fixed-width sidebar. One-shot wipe
    //   clears any stale split-view divider positions persisted by the
    //   old NavigationSplitView so every install lands on the new layout.
    static let windowResetVersion = 1

    func applicationWillFinishLaunching(_ notification: Notification) {
        WindowStateGuard.applyOnLaunch(
            appName: "PurpleIRC",
            resetVersion: Self.windowResetVersion
        )
    }
}
