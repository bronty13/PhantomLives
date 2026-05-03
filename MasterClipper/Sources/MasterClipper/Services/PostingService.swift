import Foundation
import GRDB

@MainActor
enum PostingService {

    /// Returns clips whose persona is in the site's scope and that have *not* been
    /// marked posted to this site yet.
    static func clipsNotPosted(toSiteId siteId: Int64,
                               personaScope: [String]) throws -> [Clip] {
        let pool = DatabaseService.shared.dbPool
        return try pool.read { db in
            let placeholders = personaScope.map { _ in "?" }.joined(separator: ",")
            let scopeClause = personaScope.isEmpty
                ? "1=1"
                : "LOWER(c.persona_code) IN (\(placeholders))"

            var args: [DatabaseValueConvertible] = personaScope.map { $0.lowercased() }
            args.append(siteId)

            let sql = """
            SELECT c.* FROM clips c
            WHERE c.archived = 0
              AND \(scopeClause)
              AND NOT EXISTS (
                  SELECT 1 FROM clip_postings p
                  WHERE p.clip_id = c.id
                    AND p.site_id = ?
                    AND p.status = 'posted'
              )
            ORDER BY COALESCE(c.go_live_date, c.created_at) ASC, c.id ASC
            """
            return try Clip.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    static func markPosted(clipId: String, siteId: Int64, date: Date = Date()) throws {
        let now = DatabaseService.isoNow()
        let dateStr = DatabaseService.isoDate(date)
        try DatabaseService.shared.dbPool.write { db in
            let existing = try ClipPosting
                .filter(Column("clip_id") == clipId && Column("site_id") == siteId)
                .fetchOne(db)
            let row = ClipPosting(
                clipId: clipId,
                siteId: siteId,
                postedDate: dateStr,
                status: PostingStatus.posted.rawValue,
                notes: existing?.notes ?? "",
                createdAt: existing?.createdAt ?? now,
                updatedAt: now
            )
            try row.save(db)
        }
    }
}
