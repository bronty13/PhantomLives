import AppKit

/// Minimal app delegate. Ircle's top-level layout is a manual `HStack`/`VStack`
/// (no `NavigationSplitView`, no nested `HSplitView`/`VSplitView`), so it does
/// not need the `WindowStateGuard` divider-restore workaround documented in
/// docs/sidebar-layout.md. Kept as the standard hook point for future needs.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var sizeObserver: NSObjectProtocol?

    /// Below this in either dimension, a window is "degenerate" — SwiftUI gave
    /// it no real size. Our smallest real window (Settings, 460×420) sits above
    /// this, so the heuristic never touches a legitimately-sized window.
    private static let degenerate = NSSize(width: 400, height: 360)
    private static let recovery   = NSSize(width: 940, height: 620)
    private static let floorSize  = NSSize(width: 600, height: 400)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Ask once for permission to post mention / private-message banners.
        NotificationService.requestAuthorization()

        // SwiftUI's scene sizing (`.defaultSize` / `.frame(minWidth:)` /
        // `.windowResizability`) is unreliable on macOS 14+ — windows can come
        // up at a degenerate ~100×110 frame (greedy Spacers give the content no
        // finite ideal). Fix it deterministically: whenever a window becomes key
        // at a degenerate size, grow it to a usable default and pin a sensible
        // minimum. Guarded by the degeneracy threshold so it never disturbs the
        // Settings window or a window the user has legitimately sized.
        sizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            if window.frame.width < Self.degenerate.width
                || window.frame.height < Self.degenerate.height {
                window.minSize = Self.floorSize
                window.setContentSize(Self.recovery)
                window.center()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
