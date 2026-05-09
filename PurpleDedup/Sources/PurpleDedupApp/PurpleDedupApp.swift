import SwiftUI
import PurpleDedupCore

/// Phase 4 GUI shell. Same engine the CLI uses, now wired through `CachedScanEngine`
/// so second scans skip re-hashing unchanged files. Adds a Settings scene with the
/// PhantomLives-convention Backup pane and a launch-time auto-backup hook.
@main
struct PurpleDedupAppMain: App {
    @StateObject private var settingsStore = SettingsStore()
    @State private var hasRunLaunchBackup = false

    init() {
        // SwiftUI persists NavigationSplitView/NSSplitView frames in
        // UserDefaults. On Tahoe (macOS 26.x) those saved frames can have
        // stale heights that exceed the window — the saved height was
        // sometimes ~2× the visible window, which made the sidebar render
        // at 1474pt inside a 719pt window and pushed the top content (the
        // sources strip) off-screen. Clear any frame whose saved height
        // disagrees with sane bounds so SwiftUI re-fits to the live
        // window. No-op once the saved value is reasonable.
        Self.purgeStaleSplitViewFrames()
    }

    var body: some Scene {
        WindowGroup("PurpleDedup") {
            ContentView(settingsStore: settingsStore)
                .frame(minWidth: 720, minHeight: 480)
                .task {
                    if !hasRunLaunchBackup {
                        hasRunLaunchBackup = true
                        BackupRunner.runOnLaunchIfDue(settingsStore: settingsStore)
                    }
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {} // No documents.
        }

        Settings {
            SettingsView(settingsStore: settingsStore)
        }
    }

    /// Sweep `UserDefaults` for any keys that match SwiftUI's NSSplitView
    /// frame autosave format and remove them. Cheap, idempotent, and only
    /// touches keys we own. Runs once per launch in `init`, before any
    /// SwiftUI view reads them, so the next layout starts from a clean
    /// slate.
    private static func purgeStaleSplitViewFrames() {
        let d = UserDefaults.standard
        let allKeys = d.dictionaryRepresentation().keys
        for key in allKeys where key.contains("NSSplitView Subview Frames")
                              || key.contains("NSWindow Frame SwiftUI") {
            d.removeObject(forKey: key)
        }
    }
}
