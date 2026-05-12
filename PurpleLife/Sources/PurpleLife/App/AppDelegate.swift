import AppKit
import CloudKit
import Foundation

/// Minimal `NSApplicationDelegate` whose only job is to bridge silent
/// push notifications from APNS into `CloudKitSyncService`.
///
/// Why this file exists: SwiftUI's `App` lifecycle on macOS doesn't
/// expose a hook for `application(_:didReceiveRemoteNotification:…)`.
/// `@NSApplicationDelegateAdaptor` lets us attach this delegate to the
/// SwiftUI app, and the system routes remote-notification callbacks
/// through it.
///
/// We don't hold a reference to the sync service here. Wiring through
/// init ordering is brittle (`AppDelegate` is constructed by SwiftUI
/// before `AppState`); a `NotificationCenter` event keeps the two ends
/// decoupled. `CloudKitSyncService.start(...)` registers itself as an
/// observer.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Posted when a CloudKit silent push arrives. The userInfo carries
    /// the raw APNS dictionary; observers convert it via
    /// `CKNotification(fromRemoteNotificationDictionary:)`.
    static let didReceiveCloudKitPushNotification = Notification.Name(
        "PurpleLife.didReceiveCloudKitPush"
    )

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Wipe any AppKit-persisted NSSplitView subview frames before
        // the window restores. AppKit stores split-view widths in our
        // UserDefaults under keys like "NSSplitView Subview Frames
        // <some SwiftUI view path>, SidebarNavigationSplitView". A user
        // can accidentally drag the sidebar splitter past the window
        // edge, persisting an absurd width (e.g. 3087 px in a 1147 px
        // window) — the sidebar then fills the entire window on every
        // subsequent launch, and the detail pane is invisible. There's
        // no UI affordance to recover. The defensive
        // `navigationSplitViewColumnWidth` cap in `ContentView` keeps
        // FUTURE drags inside the window, but doesn't fix the persisted
        // bad value. Stripping these keys on every launch costs the
        // user nothing meaningful (column widths re-derive from the
        // SwiftUI modifier) and guarantees the app always renders.
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix("NSSplitView Subview Frames") {
            defaults.removeObject(forKey: key)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Silent pushes for CloudKit subscriptions don't need user
        // permission (no alert / sound / badge), but we still must
        // register the app for remote notifications so APNS routes
        // pushes here. Failures are logged — the 5 min recovery poll
        // in CloudKitSyncService keeps sync working without push.
        NSApplication.shared.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        // No-op. CloudKit handles APNS token bookkeeping internally
        // when we save a CKDatabaseSubscription — we don't need the
        // token for anything ourselves.
    }

    func application(_ application: NSApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NSLog("PurpleLife: APNS registration failed — \(error.localizedDescription). "
              + "CloudKit silent-push wakeups will be unavailable; the recovery poll will keep sync working.")
    }

    func application(_ application: NSApplication,
                     didReceiveRemoteNotification userInfo: [String: Any]) {
        // Forward to the sync service via NotificationCenter so we don't
        // have to hold a direct reference. Filter out anything that
        // doesn't parse as a CloudKit push so unrelated noise never
        // triggers a sync.
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else { return }
        NotificationCenter.default.post(
            name: Self.didReceiveCloudKitPushNotification,
            object: nil,
            userInfo: userInfo
        )
    }
}
