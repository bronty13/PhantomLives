import Foundation

/// Pure date logic behind the "On This Day" view: surface entries written on the
/// same month-and-day as today, in *previous* years. Entirely local — a query
/// over the entries already in memory, nothing fetched.
enum OnThisDayService {

    /// Entries from the same month+day as `today` but an earlier year, newest
    /// first. Operates over whatever entry set the caller passes (so it respects
    /// the active journal / hidden-journal filter when given `visibleEntries`).
    static func entries(from entries: [Entry], today: Date = Date(), calendar: Calendar = .current) -> [Entry] {
        let t = calendar.dateComponents([.month, .day, .year], from: today)
        return entries
            .filter { e in
                let c = calendar.dateComponents([.month, .day, .year], from: e.dateValue)
                return c.month == t.month && c.day == t.day && (c.year ?? 0) < (t.year ?? 0)
            }
            .sorted { $0.dateValue > $1.dateValue }
    }

    /// Whole years between `entryDate` and `today` (for the "N years ago" label).
    static func yearsAgo(_ entryDate: Date, today: Date = Date(), calendar: Calendar = .current) -> Int {
        max(0, calendar.dateComponents([.year], from: entryDate, to: today).year ?? 0)
    }

    /// Human label for a years-ago bucket.
    static func label(yearsAgo n: Int) -> String {
        switch n {
        case ..<1: return "Earlier this year"
        case 1:    return "1 year ago"
        default:   return "\(n) years ago"
        }
    }
}
