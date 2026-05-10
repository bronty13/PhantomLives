import XCTest
import CloudKit
@testable import PurpleLife

/// Tests the part of the silent-push pipeline that's deterministic
/// without an actual APNS round-trip: the userInfo-dict guard.
///
/// `handleSubscriptionNotification(userInfo:)` returns `false` and
/// skips the pull when the dict isn't a CloudKit push — so unrelated
/// notifications (or programmer noise) can never trigger a sync. The
/// positive path (a valid CKDatabaseSubscription push triggers a
/// `pull()`) needs a real APNS delivery to verify; that's covered by
/// the Mac→Mac trial described in `HANDOFF.md` § Phase 4 sync.
final class CloudKitSubscriptionTests: XCTestCase {

    @MainActor
    func testEmptyUserInfoIsRejected() {
        let service = CloudKitSyncService()
        XCTAssertFalse(service.handleSubscriptionNotification(userInfo: [:]))
    }

    @MainActor
    func testNonCloudKitPayloadIsRejected() {
        let service = CloudKitSyncService()
        // A user-facing alert push (e.g. from some other system that
        // also delivers via APNS) carries `aps` but no `ck` namespace.
        // CKNotification(fromRemoteNotificationDictionary:) returns nil
        // for these and our handler must do the same.
        let alertPush: [String: Any] = [
            "aps": [
                "alert": ["title": "ignore me", "body": "nothing to see"],
                "badge": 1,
            ],
        ]
        XCTAssertFalse(service.handleSubscriptionNotification(userInfo: alertPush))
    }
}
