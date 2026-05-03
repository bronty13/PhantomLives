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
}
