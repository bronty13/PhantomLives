import SwiftUI
import AppKit

@main
struct MasterClipperApp: App {
    @StateObject private var appState = AppState()

    init() {
        Self.applyWindowResetIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1100, minHeight: 700)
                .tint(EdColor.ink)
                // Editorial is intrinsically a light design (bone canvas, ink ruling).
                // Force `.light` so SwiftUI's Table / TextField / TextEditor system
                // materials resolve to light variants — otherwise on a Mac running
                // dark mode they render near-black against our bone background.
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 1400, height: 900)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            AppMenuCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(minWidth: 720, minHeight: 520)
                .preferredColorScheme(.light)
        }
    }

    // MARK: - Window-state reset

    /// Bumped whenever a future release needs to force a one-shot wipe of
    /// SwiftUI's auto-persisted window frame / split-view / sidebar state.
    /// Increment to ship another reset.
    static let windowResetVersion = 3
    static let windowResetVersionKey = "MasterClipper.windowResetVersion"

    /// SwiftUI persists window frames and sidebar collapse state via
    /// `NSWindow Frame …` keys in `UserDefaults` and a per-app saved-state
    /// bundle. Both can drift off-screen (window saved at coordinates that
    /// no longer correspond to a connected display) and stick across
    /// relaunches — close + reopen doesn't help. This wipes the stored
    /// frame + split-view + sidebar entries once per `windowResetVersion`
    /// bump, then lets SwiftUI fall back to `defaultSize` and the standard
    /// layout. After the reset future relaunches persist normally.
    /// Force-fire the reset right now, ignoring `windowResetVersion`. Used
    /// by the menubar **Window → Reset Window State…** action — it stamps a
    /// fresh sentinel so the same launch can't double-reset, then asks the
    /// user to relaunch (the wipe only takes effect on next start).
    static func forceWindowResetNow() {
        UserDefaults.standard.set(0, forKey: windowResetVersionKey)
        applyWindowResetIfNeeded()
    }

    private static func applyWindowResetIfNeeded() {
        let defaults = UserDefaults.standard
        let stored = defaults.integer(forKey: windowResetVersionKey)
        guard stored < windowResetVersion else { return }

        let snapshot = defaults.dictionaryRepresentation().keys
        var removed = 0
        for key in snapshot {
            if key.hasPrefix("NSWindow Frame")
                || key.hasPrefix("NSSplitView")
                || key.hasPrefix("NSWindow ")
                || key.hasPrefix("SwiftUI.SidebarSeparation")
                || key.contains("SidebarSplitView") {
                defaults.removeObject(forKey: key)
                removed += 1
            }
        }
        defaults.set(windowResetVersion, forKey: windowResetVersionKey)
        defaults.synchronize()

        // Also drop the AppKit "Saved Application State" snapshot for this
        // bundle — that's where window-restoration cached layout lives.
        // Best-effort; if the file isn't there or can't be removed, the
        // UserDefaults wipe above is enough on its own.
        let bundleId = Bundle.main.bundleIdentifier ?? "com.bronty13.MasterClipper"
        let savedStateDir = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Saved Application State/\(bundleId).savedState")
        try? FileManager.default.removeItem(atPath: savedStateDir)

        // Drop the leftover sandboxed-era container plist if present —
        // entitlements no longer include `app-sandbox`, so the running app
        // reads from `~/Library/Preferences/`. The container copy can hold
        // a stale frame that confuses anyone running `defaults` to debug.
        let containerPlist = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Containers/\(bundleId)/Data/Library/Preferences/\(bundleId).plist")
        try? FileManager.default.removeItem(atPath: containerPlist)

        NSLog("MasterClipper: reset window state (v\(windowResetVersion), \(removed) keys cleared)")
    }
}
