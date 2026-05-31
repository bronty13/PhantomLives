import Foundation
import UserNotifications

/// A single, optional, **local** daily reminder to journal. No network, no
/// account — `UNUserNotificationCenter` schedules a repeating calendar trigger
/// with the OS, so it fires whether or not the app is running. Authorization is
/// only requested when the user turns the reminder on.
enum NotificationService {

    static let reminderId = "com.bronty13.PurpleDiary.dailyReminder"

    /// Daily calendar trigger components for a given local time.
    static func triggerComponents(hour: Int, minute: Int) -> DateComponents {
        DateComponents(hour: max(0, min(23, hour)), minute: max(0, min(59, minute)))
    }

    /// A few gentle nudges, rotated by weekday so it isn't the same line daily.
    static let messages = [
        "A quiet moment — how was today?",
        "Time to journal ✍️",
        "What's worth remembering from today?",
        "Your journal's listening.",
        "A few words before the day closes?",
    ]

    static func body(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let weekday = (calendar.component(.weekday, from: date) - 1)
        return messages[((weekday % messages.count) + messages.count) % messages.count]
    }

    /// Ask for notification permission. Returns true if granted. Safe to call
    /// repeatedly — the system only prompts once.
    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                cont.resume(returning: granted)
            }
        }
    }

    /// Re-create the single daily reminder from settings. Removes any existing
    /// one first (idempotent), then schedules a fresh daily trigger if enabled.
    static func reschedule(enabled: Bool, hour: Int, minute: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderId])
        guard enabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "PurpleDiary"
        content.body = body()
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: triggerComponents(hour: hour, minute: minute), repeats: true)
        let request = UNNotificationRequest(identifier: reminderId, content: content, trigger: trigger)
        center.add(request)
    }
}
