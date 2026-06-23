import Foundation

/// When the automated archive should run. Drives a launchd `StartCalendarInterval`. Note
/// this only ever schedules the **archive** (export → mirror → verify → cloud) — purge is
/// never automated because it requires interactive confirmation.
public struct ArchiveSchedule: Codable, Sendable, Equatable {
    public enum Cadence: String, Codable, Sendable, CaseIterable {
        case hourly
        case daily
        case weekly
    }

    public var enabled: Bool
    public var cadence: Cadence
    public var hour: Int          // 0–23
    public var minute: Int        // 0–59
    public var weekday: Int       // 0=Sun … 6=Sat (launchd convention), used when weekly

    // Default to NOON, not the wee hours: a scheduled run blocks on the macOS
    // "access data from other apps" consent prompt until a human clicks Allow (a
    // transient, per-process TCC privilege that can't be made persistent without MDM —
    // see HANDOFF "KNOWN macOS LIMITATION"). An unattended 2 AM run just parks on that
    // prompt for hours; a waking-hours default makes it a quick once-a-day click.
    public init(enabled: Bool = false, cadence: Cadence = .daily,
                hour: Int = 12, minute: Int = 0, weekday: Int = 0) {
        self.enabled = enabled
        self.cadence = cadence
        self.hour = hour
        self.minute = minute
        self.weekday = weekday
    }

    /// The (key, value) pairs for the launchd `StartCalendarInterval` dict.
    ///  • hourly — only `Minute` (launchd fires every hour at that minute).
    ///  • daily  — `Hour` + `Minute` (every day at that time).
    ///  • weekly — `Weekday` + `Hour` + `Minute`.
    public var calendarKeys: [(key: String, value: Int)] {
        var keys: [(String, Int)] = []
        if cadence == .hourly {
            keys.append(("Minute", minute))
            return keys
        }
        if cadence == .weekly { keys.append(("Weekday", weekday)) }
        keys.append(("Hour", hour))
        keys.append(("Minute", minute))
        return keys
    }

    /// The next time this schedule will fire after `date`.
    public func nextRun(after date: Date, calendar: Calendar = .current) -> Date? {
        var comps = DateComponents()
        comps.minute = minute
        if cadence != .hourly {           // hourly matches the minute in every hour
            comps.hour = hour
        }
        if cadence == .weekly {
            comps.weekday = weekday + 1   // Calendar weekday is 1=Sun … 7=Sat
        }
        return calendar.nextDate(after: date, matching: comps, matchingPolicy: .nextTime)
    }

    public var timeString: String { String(format: "%02d:%02d", hour, minute) }

    public static let weekdayNames =
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    public var humanDescription: String {
        switch cadence {
        case .hourly: return String(format: "Every hour at :%02d", minute)
        case .daily:  return "Every day at \(timeString)"
        case .weekly:
            let name = ArchiveSchedule.weekdayNames[min(max(weekday, 0), 6)]
            return "Every \(name) at \(timeString)"
        }
    }
}
