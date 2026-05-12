import Foundation
import GRDB
import MasterClipperCore

@MainActor
enum CalendarService {

    struct GenerationResult {
        var inserted: Int
        var skipped: Int
    }

    /// Materialises blank `(date, persona)` rows for every weekday in the year
    /// where `calendar_rules.enabled = 1`. Existing rows are left alone.
    static func generateYear(_ year: Int, rules: [CalendarRule]) throws -> GenerationResult {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current

        guard
            let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
            let end   = cal.date(from: DateComponents(year: year, month: 12, day: 31))
        else {
            return GenerationResult(inserted: 0, skipped: 0)
        }

        let enabledMap: [String: Set<Int>] = Dictionary(grouping: rules.filter { $0.enabled },
                                                        by: { $0.personaCode })
            .mapValues { Set($0.map(\.weekday)) }

        var inserted = 0
        var skipped = 0
        let now = DatabaseService.isoNow()

        try DatabaseService.shared.dbPool.write { db in
            var date = start
            while date <= end {
                let weekday = cal.component(.weekday, from: date)
                let dateStr = DatabaseService.isoDate(date)
                for (persona, days) in enabledMap where days.contains(weekday) {
                    let exists = try CalendarEvent
                        .filter(Column("date") == dateStr && Column("persona_code") == persona)
                        .fetchCount(db) > 0
                    if exists {
                        skipped += 1
                        continue
                    }
                    var event = CalendarEvent(
                        id: nil,
                        date: dateStr,
                        personaCode: persona,
                        clipId: nil,
                        title: "",
                        notes: "",
                        createdAt: now,
                        updatedAt: now
                    )
                    try event.insert(db)
                    inserted += 1
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
                date = next
            }
        }

        return GenerationResult(inserted: inserted, skipped: skipped)
    }

    static func eventsByDate(start: Date, end: Date) throws -> [String: [CalendarEvent]] {
        let startStr = DatabaseService.isoDate(start)
        let endStr   = DatabaseService.isoDate(end)
        let events = try DatabaseService.shared.fetchEvents(start: startStr, end: endStr)
        return Dictionary(grouping: events, by: \.date)
    }

    static func dateRange(year: Int) -> (start: Date, end: Date)? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = cal.date(from: DateComponents(year: year, month: 12, day: 31)) else {
            return nil
        }
        return (start, end)
    }
}
