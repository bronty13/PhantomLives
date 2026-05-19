import AppKit

/// Hooks into AppKit's launch lifecycle BEFORE SwiftUI materializes the
/// first window. This is the earliest point at which we can sanitize
/// persisted window/split state — see `WindowStateGuard`.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Bump this integer when shipping a layout change that should
    /// invalidate every user's persisted window state. The next launch
    /// for each user fires a one-shot wipe (then increments their
    /// stored version so it doesn't run again).
    // v2 (2026-05-17): sidebar was still rendering below min after v1.
    //   Root cause was `Saved Application State/<bundle>.savedState`
    //   holding a stale split-view divider position that AppKit
    //   restored after the UserDefaults preflight. Preflight now wipes
    //   .savedState whenever it purges a split-view frame key.
    // v3 (2026-05-17 later same day): user reported the sidebar
    //   rendering with its content shifted off the left edge of the
    //   window — labels truncated on the LEFT, right-side counts still
    //   visible. Even with the HStack pattern (no NavigationSplitView),
    //   something in the persisted NSWindow / saved-app-state surface
    //   was anchoring content past the window's leading edge.
    //   Bumping forces a one-shot full wipe of NSWindow Frame keys,
    //   .savedState, and SidebarSeparation on every install so each
    //   user's window snaps back to defaults on next launch.
    static let windowResetVersion = 3

    private var appearanceCurrent: String = ""

    func applicationWillFinishLaunching(_ notification: Notification) {
        WindowStateGuard.applyOnLaunch(
            appName: "PurpleReel",
            resetVersion: Self.windowResetVersion
        )
        applyAppearance()
        // SwiftUI's `.preferredColorScheme(...)` only retints SwiftUI
        // surfaces — title bars, NSOpenPanel, NSAlert, and any AppKit
        // chrome continue to follow `NSApp.appearance`. Mirror the
        // Settings → Appearance pick onto the process-wide AppKit
        // appearance so chrome and content stay consistent. Defaults
        // change fires on every `set(_:forKey:)` against any key, so
        // gate the apply on a value-changed check.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.applyAppearance() }
    }

    private func applyAppearance() {
        let key = UserDefaults.standard.string(forKey: "appearance") ?? "system"
        guard key != appearanceCurrent else { return }
        appearanceCurrent = key
        switch key {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }
}
