import UIKit
import CloudKit

/// Minimal UIApplicationDelegate that exists for exactly one reason: to
/// receive CKShare acceptance callbacks. SwiftUI's `onContinueUserActivity`
/// doesn't expose the share metadata cleanly, so we bridge through
/// `UIApplicationDelegateAdaptor` and publish via NotificationCenter.
final class AppDelegate: NSObject, UIApplicationDelegate {

    static let acceptedShareNotification = Notification.Name("MasterClipper.acceptedShare")
    static let acceptedShareMetadataKey  = "metadata"

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        NotificationCenter.default.post(
            name: Self.acceptedShareNotification,
            object: nil,
            userInfo: [Self.acceptedShareMetadataKey: cloudKitShareMetadata]
        )
    }
}
