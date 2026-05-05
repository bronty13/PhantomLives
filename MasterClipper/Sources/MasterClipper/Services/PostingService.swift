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
              AND c.posting_excluded = 0
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

    /// Map of clipId → set of siteIds the clip has been posted to (status =
    /// 'posted'). One query for the whole table — used by the Posting Queue
    /// to render per-clip progress without N+1 DB hits.
    static func postedSitesByClip() throws -> [String: Set<Int64>] {
        let pool = DatabaseService.shared.dbPool
        return try pool.read { db in
            var result: [String: Set<Int64>] = [:]
            let sql = "SELECT clip_id, site_id FROM clip_postings WHERE status = 'posted'"
            let rows = try Row.fetchAll(db, sql: sql)
            for row in rows {
                let cid: String = row["clip_id"]
                let sid: Int64  = row["site_id"]
                result[cid, default: []].insert(sid)
            }
            return result
        }
    }

    static func markPosted(clipId: String, siteId: Int64, date: Date = Date()) throws {
        let now = DatabaseService.isoNow()
        let dateStr = DatabaseService.isoDate(date)
        // Read the existing row for createdAt + notes, then route the
        // write through `DatabaseService.upsertPosting` so it triggers
        // the clip-status recompute + history-row writes. Earlier this
        // wrote directly via `row.save(db)`, which left clips stuck in
        // `to_post` even after the first posting was marked posted.
        let existing = try DatabaseService.shared.dbPool.read { db in
            try ClipPosting
                .filter(Column("clip_id") == clipId && Column("site_id") == siteId)
                .fetchOne(db)
        }
        let row = ClipPosting(
            clipId: clipId,
            siteId: siteId,
            postedDate: dateStr,
            status: PostingStatus.posted.rawValue,
            notes: existing?.notes ?? "",
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        try DatabaseService.shared.upsertPosting(row)
    }
}
