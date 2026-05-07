import SwiftUI
import AppKit

/// `App` entry point. Constructs the singleton `AppState` (which fires the
/// launch-time backup before any UI reads the DB), wires the main
/// `WindowGroup` and the separate `Settings` scene, and applies the one-shot
/// window-state reset described in `applyWindowResetIfNeeded` below.
@main
struct TimelinerApp: App {
    @StateObject private var appState = AppState()

    init() {
        Self.applyWindowResetIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1100, minHeight: 700)
                .tint(appState.effectiveAccentColor)
                .preferredColorScheme(appState.preferredColorScheme)
        }
        .defaultSize(width: 1400, height: 900)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            AppMenuCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(minWidth: 760, minHeight: 540)
        }
    }

    // MARK: - Window-state reset
    //
    // SwiftUI persists window frames and sidebar collapse state via
    // `NSWindow Frame …` keys in `UserDefaults`. They can drift off-screen
    // (window saved at coordinates that no longer correspond to a connected
    // display) and stick across relaunches. This wipes the stored frame +
    // split-view + sidebar entries once per `windowResetVersion` bump, then
    // lets SwiftUI fall back to `defaultSize`. After the reset, future
    // relaunches persist normally.

    static let windowResetVersion = 1
    static let windowResetVersionKey = "Timeliner.windowResetVersion"

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

        let bundleId = Bundle.main.bundleIdentifier ?? "com.bronty13.Timeliner"
        let savedStateDir = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Saved Application State/\(bundleId).savedState")
        try? FileManager.default.removeItem(atPath: savedStateDir)

        NSLog("Timeliner: reset window state (v\(windowResetVersion), \(removed) keys cleared)")
    }
}
