import Foundation
import AppKit

/// Drop-in defense against SwiftUI's `NavigationSplitView` / `NSWindow`
/// saving a sidebar (or pane) width that's smaller than its declared
/// minimum — or larger than the current window — and stranding the user
/// with a broken layout on every relaunch.
///
/// This helper is **the canonical fix for every PhantomLives macOS app**.
/// PurpleDiary uses the manual-HStack sidebar pattern (no top-level
/// `NavigationSplitView`), so the top-level chrome is already bulletproof,
/// but the guard still runs to keep any nested split-views clean and to
/// give the user a recovery affordance.
///
/// ## What it does
///
/// On every launch (`applicationWillFinishLaunching` — BEFORE SwiftUI's
/// `WindowGroup` materializes the first window):
///
/// 1. **Preflight purge** (runs every launch): strips all
///    `"NSSplitView Subview Frames *"` keys from `UserDefaults` and wipes
///    the bundle's `.savedState` directory whenever a stale key was found.
/// 2. **Versioned one-shot reset** (runs only when `resetVersion`
///    increments): wipes the *entire* window-state surface. Bump
///    `resetVersion` in source to invalidate every install on next launch.
enum WindowStateGuard {

    /// Call from `applicationWillFinishLaunching`. Safe to call repeatedly.
    static func applyOnLaunch(appName: String, resetVersion: Int = 1) {
        preflightPurgeSplitViewFrames()
        applyVersionedResetIfNeeded(appName: appName, resetVersion: resetVersion)
    }

    /// Force a full reset on demand (wire to a "Reset Window State…" menu item).
    static func forceReset(appName: String, resetVersion: Int = 1) {
        UserDefaults.standard.set(0, forKey: resetVersionKey(appName: appName))
        applyVersionedResetIfNeeded(appName: appName, resetVersion: resetVersion)
    }

    // MARK: - Private

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
