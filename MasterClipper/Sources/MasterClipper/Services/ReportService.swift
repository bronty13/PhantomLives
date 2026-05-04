import Foundation
import GRDB

@MainActor
enum ReportService {

    // Posting status — for each (clip, site in scope), is it posted?
    struct PostingStatusRow: Identifiable {
        let id: String                         // composite "clipId-siteId"
        let clipId: String
        let clipTitle: String
        let personaCode: String
        let siteCode: String
        let siteName: String
        let posted: Bool
        let postedDate: String?
    }

    static func postingStatus(appState: AppState) -> [PostingStatusRow] {
        let postings = (try? DatabaseService.shared.dbPool.read { db in
            try ClipPosting.fetchAll(db)
        }) ?? []
        let postingByPair: [String: ClipPosting] = Dictionary(uniqueKeysWithValues:
            postings.map { ("\($0.clipId)-\($0.siteId)", $0) }
        )

        var rows: [PostingStatusRow] = []
        for clip in appState.clips where !clip.archived {
            for site in appState.sites where !site.archived && site.appliesTo(personaCode: clip.personaCode) {
                guard let sid = site.id else { continue }
                let key = "\(clip.id)-\(sid)"
                let p = postingByPair[key]
                rows.append(PostingStatusRow(
                    id: key,
                    clipId: clip.id,
                    clipTitle: clip.title.isEmpty ? "(untitled)" : clip.title,
                    personaCode: clip.personaCode,
                    siteCode: site.code,
                    siteName: site.displayName,
                    posted: p?.statusEnum == .posted,
                    postedDate: p?.postedDate
                ))
            }
        }
        return rows
    }

    // Category usage — count of clips per category
    struct CategoryUsageRow: Identifiable {
        let id: Int64
        let name: String
        let clipCount: Int
    }

    static func categoryUsage() -> [CategoryUsageRow] {
        let pool = DatabaseService.shared.dbPool
        return (try? pool.read { db in
            let sql = """
            SELECT c.id, c.name, COUNT(cc.clip_id) AS n
            FROM categories c
            LEFT JOIN clip_categories cc ON cc.category_id = c.id
            WHERE c.archived = 0
            GROUP BY c.id
            ORDER BY n DESC, c.name ASC
            """
            return try Row.fetchAll(db, sql: sql).map { row in
                CategoryUsageRow(
                    id: row["id"] ?? 0,
                    name: row["name"] ?? "",
                    clipCount: row["n"] ?? 0
                )
            }
        }) ?? []
    }

    // Calendar — events per persona × month
    struct CalendarMonthRow: Identifiable {
        let id: String                         // "yyyy-MM-persona"
        let yearMonth: String
        let personaCode: String
        let count: Int
    }

    static func calendarRollup(year: Int) -> [CalendarMonthRow] {
        let pool = DatabaseService.shared.dbPool
        return (try? pool.read { db in
            let sql = """
            SELECT substr(date, 1, 7) AS ym, persona_code, COUNT(*) AS n
            FROM calendar_events
            WHERE date >= ? AND date <= ?
            GROUP BY ym, persona_code
            ORDER BY ym, persona_code
            """
            let start = "\(year)-01-01"
            let end   = "\(year)-12-31"
            return try Row.fetchAll(db, sql: sql, arguments: [start, end]).map { row in
                let ym: String      = row["ym"] ?? ""
                let p:  String      = row["persona_code"] ?? ""
                let n:  Int         = row["n"] ?? 0
                return CalendarMonthRow(id: "\(ym)-\(p)", yearMonth: ym, personaCode: p, count: n)
            }
        }) ?? []
    }

    // MARK: - Weekly rollup

    /// Three-week go-live preview + a list of clips not yet in `production`.
    /// Week boundaries respect `settings.calendarFirstWeekday`.
    struct WeeklyRollup {
        struct Item: Identifiable {
            let clip: Clip
            var id: String { clip.id }
        }
        let lastWeek:        [Item]
        let thisWeek:        [Item]
        let nextWeek:        [Item]
        let notInProduction: [Item]
        let lastWeekRange:  (start: Date, end: Date)
        let thisWeekRange:  (start: Date, end: Date)
        let nextWeekRange:  (start: Date, end: Date)
    }

    static func weeklyRollup(appState: AppState, anchor: Date = Date()) -> WeeklyRollup {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone   = .current
        cal.firstWeekday = max(1, min(7, appState.settings.calendarFirstWeekday))

        let interval = cal.dateInterval(of: .weekOfYear, for: anchor)
            ?? DateInterval(start: anchor, duration: 7 * 86400)
        let thisStart = interval.start
        let thisEnd   = interval.end                          // start of next week
        let lastStart = cal.date(byAdding: .day, value: -7, to: thisStart) ?? thisStart
        let lastEnd   = thisStart
        let nextStart = thisEnd
        let nextEnd   = cal.date(byAdding: .day, value: 7, to: thisEnd) ?? thisEnd

        let isoFmt = DateFormatter()
        isoFmt.dateFormat = "yyyy-MM-dd"
        isoFmt.locale = Locale(identifier: "en_US_POSIX")

        let active = appState.clips.filter { !$0.archived }

        func inRange(_ clip: Clip, start: Date, end: Date) -> Bool {
            guard let go = clip.goLiveDate, !go.isEmpty,
                  let date = isoFmt.date(from: go) else { return false }
            return date >= start && date < end
        }

        let byGoLive: (Clip, Clip) -> Bool = { ($0.goLiveDate ?? "") < ($1.goLiveDate ?? "") }

        let lastWeek = active.filter { inRange($0, start: lastStart, end: lastEnd) }
            .sorted(by: byGoLive).map { WeeklyRollup.Item(clip: $0) }
        let thisWeek = active.filter { inRange($0, start: thisStart, end: thisEnd) }
            .sorted(by: byGoLive).map { WeeklyRollup.Item(clip: $0) }
        let nextWeek = active.filter { inRange($0, start: nextStart, end: nextEnd) }
            .sorted(by: byGoLive).map { WeeklyRollup.Item(clip: $0) }
        let notInProduction = active.filter { $0.statusEnum != .production }
            .sorted { lhs, rhs in
                if lhs.statusEnum.sortOrder != rhs.statusEnum.sortOrder {
                    return lhs.statusEnum.sortOrder < rhs.statusEnum.sortOrder
                }
                return lhs.title < rhs.title
            }
            .map { WeeklyRollup.Item(clip: $0) }

        return WeeklyRollup(
            lastWeek: lastWeek, thisWeek: thisWeek, nextWeek: nextWeek,
            notInProduction: notInProduction,
            lastWeekRange: (lastStart, lastEnd),
            thisWeekRange: (thisStart, thisEnd),
            nextWeekRange: (nextStart, nextEnd)
        )
    }
}
