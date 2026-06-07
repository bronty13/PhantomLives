import AppKit

/// Wires the two launch-time PhantomLives standards: the window-state guard
/// (before SwiftUI materializes a window) and auto-backup-on-launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the App so the backup can read settings. Created early in the App
    /// init, assigned here.
    static var settingsStore: SettingsStore?

    /// Routes a file opened from Finder ("Open With Purple Archive" / double-
    /// click) into the SwiftUI model. The view installs this on first appear.
    /// Assigning a non-nil handler immediately drains any URLs that arrived
    /// before the model existed (open events can fire before the window does at
    /// cold launch).
    static var openHandler: ((URL) -> Void)? {
        didSet {
            guard let openHandler else { return }
            let pending = pendingURLs
            pendingURLs = []
            pending.forEach(openHandler)
        }
    }

    /// Files that arrived from Finder before `openHandler` was installed.
    private static var pendingURLs: [URL] = []

    /// Finder "Open With" / double-click / `open -a` entry point. Without this,
    /// the document types declared in Info.plist let Finder offer the app but
    /// the chosen archive never reaches it (a WindowGroup app, unlike a
    /// DocumentGroup, gets no automatic file routing).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let handler = Self.openHandler {
                handler(url)
            } else {
                Self.pendingURLs.append(url)
            }
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        WindowStateGuard.applyOnLaunch(appName: "PurpleArchive", resetVersion: 1)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let store = Self.settingsStore {
            BackupService.runOnLaunchIfDue(settingsStore: store)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
