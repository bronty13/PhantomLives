import Foundation
import UserNotifications
import AppKit

/// Schedules calendar-anniversary reminders for case events.
///
/// Permission flow: never request authorization at launch. Only ask when the
/// user explicitly enables the feature in Settings → Notifications. If the
/// user previously denied, show a hint pointing to System Settings instead.
///
/// Scheduling: for every event whose importance meets the configured floor
/// (`AppSettings.anniversaryMinImportance`), the next-occurrence anniversary
/// (year >= today) is computed; if it falls within the lookahead window, a
/// `UNCalendarNotificationTrigger` is registered. All Timeliner-scheduled
/// reminders use the identifier prefix `"timeliner.anniversary.<event-id>"`
/// so they can be cleared and re-scheduled wholesale on data changes.
@MainActor
final class NotificationsService {
    static let shared = NotificationsService()

    private let identifierPrefix = "timeliner.anniversary."
    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - Authorization

    enum Authorization: String {
        case notDetermined
        case authorized
        case denied
        case ephemeral

        init(_ status: UNAuthorizationStatus) {
            switch status {
            case .notDetermined: self = .notDetermined
            case .authorized, .provisional: self = .authorized
            case .denied: self = .denied
            case .ephemeral: self = .ephemeral
            @unknown default: self = .notDetermined
            }
        }

        var label: String {
            switch self {
            case .notDetermined: return "Not requested yet"
            case .authorized:    return "Authorized"
            case .denied:        return "Denied (open System Settings → Notifications → Timeliner)"
            case .ephemeral:     return "Ephemeral"
            }
        }
    }

    func currentAuthorization() async -> Authorization {
        let settings = await center.notificationSettings()
        return Authorization(settings.authorizationStatus)
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            NSLog("Timeliner: notification auth request failed — \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Scheduling

    /// Replace every Timeliner anniversary reminder currently registered
    /// with a fresh set computed from `events`. Quietly no-ops if reminders
    /// are disabled or authorization is missing.
    func reschedule(events: [Event], cases: [Case], settings: AppSettings) async {
        // Always clear our prefix first so toggling the feature off cancels
        // pending notifications without leaving stragglers behind.
        await clearScheduled()
        guard settings.anniversaryRemindersEnabled else { return }
        let auth = await currentAuthorization()
        guard auth == .authorized || auth == .ephemeral else { return }

        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let lookaheadEnd = cal.date(byAdding: .day, value: max(1, settings.anniversaryLookaheadDays), to: now) ?? now
        let minImp = Importance(rawValue: settings.anniversaryMinImportance) ?? .medium

        let casesById = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0) })

        for ev in events {
            guard ev.importanceEnum.sortOrder >= minImp.sortOrder,
                  let original = ev.parsedStart else { continue }
            guard let nextAnniversary = nextAnniversary(after: now, of: original, hour: settings.anniversaryNotificationHour) else { continue }
            guard nextAnniversary <= lookaheadEnd else { continue }

            let yearsAgo = cal.component(.year, from: nextAnniversary) - cal.component(.year, from: original)
            let caseTitle = casesById[ev.caseId]?.title ?? ""

            let content = UNMutableNotificationContent()
            content.title = ev.title.isEmpty ? "Timeliner anniversary" : ev.title
            if yearsAgo == 1 {
                content.subtitle = "1 year ago today"
            } else if yearsAgo > 0 {
                content.subtitle = "\(yearsAgo) years ago today"
            }
            if !caseTitle.isEmpty {
                content.body = caseTitle
            }
            content.sound = .default

            var triggerComponents = cal.dateComponents([.year, .month, .day, .hour, .minute], from: nextAnniversary)
            triggerComponents.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(identifierPrefix)\(ev.id)",
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
            } catch {
                NSLog("Timeliner: failed to schedule anniversary for \(ev.id) — \(error.localizedDescription)")
            }
        }
    }

    /// Cancel every Timeliner-scheduled anniversary reminder. Leaves any
    /// other apps' notifications alone (we filter on the prefix).
    func clearScheduled() async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending
            .filter { $0.identifier.hasPrefix(identifierPrefix) }
            .map(\.identifier)
        if !ours.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
    }

    /// Returns the count of currently-pending Timeliner reminders. Used by
    /// the Settings tab to surface "8 reminders scheduled" feedback.
    func pendingCount() async -> Int {
        let pending = await center.pendingNotificationRequests()
        return pending.filter { $0.identifier.hasPrefix(identifierPrefix) }.count
    }

    /// Fire a small banner immediately so the user can verify the alert
    /// settings work end-to-end without waiting for a real anniversary.
    func fireTestNotification() async {
        let auth = await currentAuthorization()
        guard auth == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Timeliner test notification"
        content.body = "Anniversary reminders are wired up."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "timeliner.test.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    /// Reveal the Notifications pane of System Settings — the only escape
    /// route once the user has answered "Don't Allow" and notifications are
    /// stuck in `.denied`.
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Date math

    /// Next occurrence of `original`'s month-and-day at or after `start`,
    /// at the configured hour. Returns nil if the date math fails.
    private func nextAnniversary(after start: Date, of original: Date, hour: Int) -> Date? {
        let cal = Calendar(identifier: .gregorian)
        let originalComps = cal.dateComponents([.month, .day], from: original)
        let startComps = cal.dateComponents([.year, .month, .day], from: start)
        guard let month = originalComps.month, let day = originalComps.day,
              let startYear = startComps.year else { return nil }
        let clampedHour = min(max(hour, 0), 23)

        for offset in 0...1 {
            var comps = DateComponents()
            comps.year = startYear + offset
            comps.month = month
            comps.day = day
            comps.hour = clampedHour
            comps.minute = 0
            if let candidate = cal.date(from: comps), candidate > start {
                return candidate
            }
        }
        return nil
    }
}
