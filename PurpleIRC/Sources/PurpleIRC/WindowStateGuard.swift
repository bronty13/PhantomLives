import Foundation
import AppKit

/// Drop-in defense against SwiftUI's `NavigationSplitView` / `NSWindow`
/// saving a sidebar (or pane) width that's smaller than its declared
/// minimum — or larger than the current window — and stranding the user
/// with a broken layout on every relaunch.
///
/// The bug, in one sentence: AppKit stores split-view subview frames in
/// `UserDefaults` under keys like `"NSSplitView Subview Frames <path>"`,
/// the user can drag the divider past `navigationSplitViewColumnWidth`'s
/// declared min, and SwiftUI does not re-clamp on restore. The sidebar
/// then renders at the persisted (broken) width forever.
///
/// This helper is **the canonical fix for every PhantomLives macOS app**.
/// PurpleIRC's top-level chrome no longer uses `NavigationSplitView` (it's
/// a manual `HStack` in `ContentView`), but the guard still runs to keep
/// any nested split state and stale `.savedState` clean across launches.
///
/// ## What it does
///
/// On every launch (`applicationWillFinishLaunching` — BEFORE SwiftUI's
/// `WindowGroup` materializes the first window):
///
/// 1. **Preflight purge** (runs every launch): strips all
///    `"NSSplitView Subview Frames *"` keys from `UserDefaults` and wipes
///    the bundle's `.savedState` directory when any stale frame key was
///    found. SwiftUI re-derives widths from source.
///
/// 2. **Versioned one-shot reset** (runs only when `resetVersion`
///    increments): wipes the *entire* window-state surface —
///    `NSWindow Frame *`, `SwiftUI.SidebarSeparation`, the
///    `Saved Application State` directory, plus any keys containing
///    `SidebarSplitView`. Bump `resetVersion` in source to invalidate
///    every install on its next launch.
enum WindowStateGuard {

    /// Call from `applicationWillFinishLaunching` (or earliest possible
    /// AppKit hook). Safe to call multiple times — no-ops after the
    /// first invocation in a given launch.
    /// - Parameters:
    ///   - appName: human-readable app name; used only for logging.
    ///   - resetVersion: monotonically increasing integer. Bump when
    ///     you've shipped a layout change and want to invalidate every
    ///     user's persisted window state.
    static func applyOnLaunch(appName: String, resetVersion: Int = 1) {
        preflightPurgeSplitViewFrames()
        applyVersionedResetIfNeeded(appName: appName, resetVersion: resetVersion)
    }

    /// Force a full reset on demand (wire to a "Reset Window State…"
    /// menu item). Bumps the stored version to 0 and re-runs the
    /// versioned reset path so the wipe happens immediately.
    static func forceReset(appName: String, resetVersion: Int = 1) {
        UserDefaults.standard.set(0, forKey: resetVersionKey(appName: appName))
        applyVersionedResetIfNeeded(appName: appName, resetVersion: resetVersion)
    }

    // MARK: - Private

    /// Step 1: idempotent purge of split-view subview frames AND the
    /// matching AppKit "Saved Application State" directory. AppKit
    /// persists split-view divider positions in BOTH UserDefaults
    /// (under `NSSplitView Subview Frames`) and the bundle's
    /// `.savedState` directory. Purging only UserDefaults still leaves
    /// the bad width in `.savedState`, and AppKit happily restores it.
    /// Wiping `.savedState` whenever we purge a stale frame key forces
    /// the full restoration path to fall back to SwiftUI defaults.
    private static func preflightPurgeSplitViewFrames() {
        let defaults = UserDefaults.standard
        var removed = 0
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix("NSSplitView Subview Frames") {
            defaults.removeObject(forKey: key)
            removed += 1
        }
        if removed > 0 {
            // Nuke the bundle's Saved Application State directory too.
            // AppKit will recreate it on next save, but without the
            // stale split-view restoration data.
            if let bundleId = Bundle.main.bundleIdentifier {
                let savedStateDir = (NSHomeDirectory() as NSString)
                    .appendingPathComponent("Library/Saved Application State/\(bundleId).savedState")
                try? FileManager.default.removeItem(atPath: savedStateDir)
            }
            NSLog("[WindowStateGuard] preflight purged \(removed) NSSplitView frame key(s) + .savedState")
        }
    }

    /// Step 2: versioned, one-shot, broad wipe. Run only when the
    /// stored version is below the source-declared version.
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
