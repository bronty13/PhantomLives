import Foundation
import AppKit

/// Drop-in defense against SwiftUI's `NavigationSplitView` / `NSWindow` saving a sidebar
/// (or pane) width smaller than its declared minimum and stranding the user with a broken
/// layout on every relaunch. The canonical PhantomLives fix — copied verbatim from
/// PurpleReel. PurpleAttic uses a manual `HStack` sidebar (no `NavigationSplitView`), but
/// this still keeps any nested `HSplitView`/`VSplitView` clean.
enum WindowStateGuard {

    static func applyOnLaunch(appName: String, resetVersion: Int = 1) {
        preflightPurgeSplitViewFrames()
        applyVersionedResetIfNeeded(appName: appName, resetVersion: resetVersion)
    }

    static func forceReset(appName: String, resetVersion: Int = 1) {
        UserDefaults.standard.set(0, forKey: resetVersionKey(appName: appName))
        applyVersionedResetIfNeeded(appName: appName, resetVersion: resetVersion)
    }

    private static func preflightPurgeSplitViewFrames() {
        let defaults = UserDefaults.standard
        var removed = 0
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix("NSSplitView Subview Frames") {
            defaults.removeObject(forKey: key)
            removed += 1
        }
        if removed > 0 {
            if let bundleId = Bundle.main.bundleIdentifier {
                let savedStateDir = (NSHomeDirectory() as NSString)
                    .appendingPathComponent("Library/Saved Application State/\(bundleId).savedState")
                try? FileManager.default.removeItem(atPath: savedStateDir)
            }
            NSLog("[WindowStateGuard] preflight purged \(removed) NSSplitView frame key(s) + .savedState")
        }
    }

    private static func applyVersionedResetIfNeeded(appName: String, resetVersion: Int) {
        let defaults = UserDefaults.standard
        let key = resetVersionKey(appName: appName)
        let stored = defaults.integer(forKey: key)
        guard stored < resetVersion else { return }

        let snapshot = defaults.dictionaryRepresentation().keys
        var removed = 0
        for k in snapshot {
            if k.hasPrefix("NSWindow Frame")
                || k.hasPrefix("NSSplitView")
                || k.hasPrefix("NSWindow ")
                || k.hasPrefix("SwiftUI.SidebarSeparation")
                || k.contains("SidebarSplitView") {
                defaults.removeObject(forKey: k)
                removed += 1
            }
        }
        defaults.set(resetVersion, forKey: key)
        defaults.synchronize()

        let bundleId = Bundle.main.bundleIdentifier ?? "com.bronty13.\(appName)"
        let savedStateDir = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Saved Application State/\(bundleId).savedState")
        try? FileManager.default.removeItem(atPath: savedStateDir)

        NSLog("[WindowStateGuard] \(appName): reset window state (v\(resetVersion), \(removed) keys cleared)")
    }

    private static func resetVersionKey(appName: String) -> String {
        "\(appName).windowResetVersion"
    }
}
