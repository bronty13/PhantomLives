import Foundation

/// Cadence repeat rule for `Cadenced Activities`. When a cadenced Matter is
/// transitioned to `Closed`, `CadenceService` clones it into a fresh Matter
/// with `due_at` shifted forward by `nextDueOffset`.
enum CadenceKind: String, Codable, CaseIterable, Hashable {
    case daily, weekly, biweekly, monthly, quarterly, semiannual, annual, custom

    var displayName: String {
        switch self {
        case .daily:      return "Daily"
        case .weekly:     return "Weekly"
        case .biweekly:   return "Bi-weekly"
        case .monthly:    return "Monthly"
        case .quarterly:  return "Quarterly"
        case .semiannual: return "Semi-annually"
        case .annual:     return "Annually"
        case .custom:     return "Custom (every N days)"
        }
    }
}

struct Cadence: Codable, Hashable, Identifiable {
    var id: String                  // UUID
    var kind: CadenceKind
    var customIntervalDays: Int?    // populated only when kind == .custom

    /// Add the cadence period to the given date. For calendar-based kinds
    /// (monthly / quarterly / annual) we use Calendar arithmetic so end-of-
    /// month behavior matches user intuition (Jan 31 → Feb 28, not Mar 3).
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date {
        switch kind {
        case .daily:      return calendar.date(byAdding: .day,    value: 1,  to: date) ?? date
        case .weekly:     return calendar.date(byAdding: .day,    value: 7,  to: date) ?? date
        case .biweekly:   return calendar.date(byAdding: .day,    value: 14, to: date) ?? date
        case .monthly:    return calendar.date(byAdding: .month,  value: 1,  to: date) ?? date
        case .quarterly:  return calendar.date(byAdding: .month,  value: 3,  to: date) ?? date
        case .semiannual: return calendar.date(byAdding: .month,  value: 6,  to: date) ?? date
        case .annual:     return calendar.date(byAdding: .year,   value: 1,  to: date) ?? date
        case .custom:
            let n = max(customIntervalDays ?? 1, 1)
            return calendar.date(byAdding: .day, value: n, to: date) ?? date
        }
    }
}
