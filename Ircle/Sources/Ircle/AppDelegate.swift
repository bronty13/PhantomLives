import AppKit

/// Minimal app delegate. Ircle's top-level layout is a manual `HStack`/`VStack`
/// (no `NavigationSplitView`, no nested `HSplitView`/`VSplitView`), so it does
/// not need the `WindowStateGuard` divider-restore workaround documented in
/// docs/sidebar-layout.md. Kept as the standard hook point for future needs.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var sizeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // SwiftUI's WindowGroup sizing (`.defaultSize` / `.frame(minWidth:)` /
        // `.windowResizability`) is unreliable on macOS 14+ — the window can
        // come up at a degenerate ~100×125 frame. Fix it deterministically:
        // when the WindowGroup window first becomes key (i.e. after SwiftUI has
        // created and laid it out), enforce a minimum size and grow a too-small
        // window to a sensible default. Runs once, then stops observing.
        sizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let window = note.object as? NSWindow else { return }
            window.minSize = NSSize(width: 720, height: 460)
            if window.frame.width < 720 || window.frame.height < 460 {
                window.setContentSize(NSSize(width: 940, height: 620))
                window.center()
            }
            if let obs = self.sizeObserver {
                NotificationCenter.default.removeObserver(obs)
                self.sizeObserver = nil
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
