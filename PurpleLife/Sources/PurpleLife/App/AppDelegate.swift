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
