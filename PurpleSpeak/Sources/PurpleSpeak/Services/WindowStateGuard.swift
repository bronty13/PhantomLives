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
/// Adopt it before the first build (alongside the app icon convention
/// in `feedback_app_icon_before_build`).
///
/// ## Usage
///
/// 1. Drop this file into the app's `Sources/<AppName>/Services/`.
/// 2. Add an `AppDelegate.swift` (or extend an existing one) and wire:
///    ```swift
///    final class AppDelegate: NSObject, NSApplicationDelegate {
///        func applicationWillFinishLaunching(_ notification: Notification) {
///            WindowStateGuard.applyOnLaunch(
///                appName: "PurpleReel",
///                resetVersion: 1
///            )
///        }
///    }
///    ```
/// 3. Adapter into the `@main App`:
///    ```swift
///    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
///    ```
/// 4. On EVERY `NavigationSplitView` / `HSplitView` / `VSplitView`
///    column, apply explicit min **AND** max widths:
///    ```swift
///    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
///    ```
///    Max matters: it caps future drags inside a sane range so the
///    persisted value never goes wildly out of band.
/// 5. Add a "Reset Window State…" menu item that calls
///    `WindowStateGuard.forceReset(appName: …)` so the user has a
///    recovery affordance if a future state corruption slips past.
///
/// ## What it does
///
/// On every launch (`applicationWillFinishLaunching` — BEFORE SwiftUI's
/// `WindowGroup` materializes the first window):
///
/// 1. **Preflight purge** (PurpleLife pattern, runs every launch):
///    strips all `"NSSplitView Subview Frames *"` keys from
///    `UserDefaults`. SwiftUI re-derives widths from
///    `navigationSplitViewColumnWidth` modifiers. The user loses the
///    custom width they set last session — that's the trade — but the
///    app always renders.
///
/// 2. **Versioned one-shot reset** (Timeliner pattern, runs only when
///    `resetVersion` increments): wipes the *entire* window-state
///    surface — `NSWindow Frame *`, `SwiftUI.SidebarSeparation`, the
///    `Saved Application State` directory, plus any keys containing
///    `SidebarSplitView`. Use this when you've shipped a fix that
///    requires invalidating prior persisted state across all users.
///    Bump `resetVersion` in source; every existing install fixes
///    itself on next launch with no user action.
///
/// See `feedback_split_view_state_guard` in `~/.claude/memory` for the
/// project-wide convention behind this helper.
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
    /// Cheap, runs every launch. The user trades their custom column
    /// width and window-position-restoration-from-savedState for
    /// guaranteed renderability — the regular `NSWindow Frame …` key
    /// in UserDefaults still preserves window position across launches.
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
