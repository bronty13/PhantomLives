import Foundation
import UserNotifications

/// Thin, never-throwing wrapper over `UNUserNotificationCenter` for mention /
/// private-message alerts. No-ops if the user hasn't granted permission.
enum NotificationService {

    /// `UNUserNotificationCenter.current()` aborts (SIGABRT) when the process has
    /// no application bundle — e.g. under `swift test`. Gate every entry point on
    /// a real bundle id so the engine stays unit-testable.
    private static var available: Bool { Bundle.main.bundleIdentifier != nil }

    /// Ask once (at launch) for permission to post alerts + sounds. Safe to call
    /// even if the user later denies — posting just becomes a no-op.
    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Post a banner. `id` is stable per conversation so a burst of messages
    /// coalesces into one replaced banner rather than a stack.
    static func post(title: String, body: String, id: String) {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }
}
