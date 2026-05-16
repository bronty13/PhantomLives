import Foundation
import GRDB

/// Phase 2 full-text search. Backed by SQLite FTS5 over the decrypted
/// `fields_json` content. Index is maintained incrementally by hooks in
/// `ObjectEngine` (insert / update / delete) and rebuilt from scratch on
/// app launch via `reindexAll(schema:)` so a missed write or a restored
/// backup never leaves stale rows.
@MainActor
enum SearchService {

    struct Hit: Identifiable, Equatable {
        var id: String { recordId }
        let recordId: String
        let typeId: String
        let title: String
        let body: String
    }

    /// Wipe and rebuild the full-text index. Called from `AppState` on
    /// launch and after a backup restore.
    static func reindexAll(schema: SchemaRegistry) {
        do {
            let db = DatabaseService.shared
            let allObjects = try db.fetchAllObjects()
            try db.dbPool.write { dbq in
                try dbq.execute(sql: "DELETE FROM objects_fts")
                for obj in allObjects {
                    guard let type = schema.type(id: obj.typeId) else { continue }
                    let (title, body) = searchableText(for: obj, type: type)
                    try dbq.execute(
                        sql: """
                            INSERT INTO objects_fts (object_id, type_id, title, body)
                            VALUES (?, ?, ?, ?)
                        """,
                        arguments: [obj.id, obj.typeId, title, body]
                    )
                }
            }
        } catch {
            NSLog("PurpleLife: reindexAll failed — \(error.localizedDescription)")
        }
    }

    /// Insert or update a single record's FTS row. Called from
    /// ObjectEngine after every successful create / update.
    static func upsert(record: ObjectRecord, type: ObjectType) {
        do {
            let (title, body) = searchableText(for: record, type: type)
            try DatabaseService.shared.dbPool.write { db in
                // FTS5 has no native UPSERT — replace by id.
                try db.execute(
                    sql: "DELETE FROM objects_fts WHERE object_id = ?",
                    arguments: [record.id]
                )
                try db.execute(
                    sql: """
                        INSERT INTO objects_fts (object_id, type_id, title, body)
                        VALUES (?, ?, ?, ?)
                    """,
                    arguments: [record.id, record.typeId, title, body]
                )
            }
        } catch {
            NSLog("PurpleLife: SearchService.upsert failed — \(error.localizedDescription)")
        }
    }

    /// Remove a record's FTS row. Called from ObjectEngine after delete.
    static func delete(recordId: String) {
        do {
            try DatabaseService.shared.dbPool.write { db in
                try db.execute(
                    sql: "DELETE FROM objects_fts WHERE object_id = ?",
                    arguments: [recordId]
                )
            }
        } catch {
            NSLog("PurpleLife: SearchService.delete failed — \(error.localizedDescription)")
        }
    }

    /// Run a query. Empty / whitespace-only queries return `[]`. The
    /// tokenizer is `porter` so prefix-style queries are forgiving;
    /// callers don't need to massage the input.
    ///
    /// `excludingTypeIds` filters out hits whose `type_id` is in the
    /// set — Quick Switcher and other surfaces pass
    /// `schema.vaultTypeIds` when the Vault is locked so Vault records
    /// never leak through search. Done at the SQL layer rather than
    /// post-fetch so the `limit` is honored against the visible set,
    /// not the underlying set.
    static func search(_ query: String, limit: Int = 50, excludingTypeIds: Set<String> = []) -> [Hit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        // FTS5 prefix-match each token so typing "ada" finds "Adam" too.
        let tokens = trimmed
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { sanitize($0) + "*" }
        let pattern = tokens.joined(separator: " ")

        do {
            return try DatabaseService.shared.dbPool.read { db in
                var sql = """
                    SELECT object_id, type_id, title, body
                    FROM objects_fts
                    WHERE objects_fts MATCH ?
                """
                var args: [DatabaseValueConvertible] = [pattern]
                if !excludingTypeIds.isEmpty {
                    let placeholders = Array(repeating: "?", count: excludingTypeIds.count).joined(separator: ", ")
                    sql += " AND type_id NOT IN (\(placeholders))"
                    args.append(contentsOf: excludingTypeIds.sorted())
                }
                sql += " ORDER BY rank LIMIT ?"
                args.append(limit)
                return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).map { row in
                    Hit(
                        recordId: row["object_id"],
                        typeId: row["type_id"],
                        title: row["title"],
                        body: row["body"]
                    )
                }
            }
        } catch {
            NSLog("PurpleLife: SearchService.search failed — \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Advanced search (tags Increment 3a)

    /// Tag-matching shape. `.any` (OR) succeeds when a record carries
    /// *any* of the required tag ids. `.all` (AND) requires *every*
    /// id to be present. Trivially `.any` when only one tag is
    /// required — UI only surfaces the toggle for 2+ tags.
    enum TagMatchMode: String, Equatable {
        case any
        case all
    }

    /// Composed search predicate. Used by the advanced Search window
    /// (tags Increment 3) and any other surface that needs more than
    /// the bare free-text path. Passing an all-default filter is
    /// equivalent to "every record, newest first" — a useful "what's
    /// in here?" baseline.
    struct Filter: Equatable {
        var query: String = ""
        /// Restrict to these type ids. nil or empty = no type
        /// restriction (all visible types). The Vault gating layer
        /// in `SearchScreen` populates this from the user's chip
        /// selection.
        var typeIds: Set<String>? = nil
        /// Always-excluded type ids. The Vault uses this when locked
        /// (or unlocked + "Include Vault" unchecked) to keep Vault
        /// records out of the result set regardless of the user's
        /// type-chip selection.
        var excludingTypeIds: Set<String> = []
        /// Required tag ids (empty = no tag filter).
        var requiredTagIds: Set<String> = []
        /// AND or OR across `requiredTagIds`. Ignored when the set
        /// has <= 1 element.
        var tagMatchMode: TagMatchMode = .any
        /// When true, only records carrying NO tags are returned.
        /// Mutually exclusive with `requiredTagIds`; if both are
        /// set, `requiredTagIds` wins (it's the more specific
        /// filter and the UI never lets the user set both).
        var untaggedOnly: Bool = false
        /// Inclusive range on `objects.updated_at`. Either bound
        /// may be nil for an open-ended range.
        var dateRange: ClosedDateRange? = nil
        var limit: Int = 200
    }

    /// Half-open inclusive date range used by `Filter.dateRange`.
    /// `from` and `to` are bounded to whole-day boundaries by the UI
    /// where appropriate (Today's "this week" uses midnight-to-now);
    /// the comparison is straight ISO-8601 string compare against
    /// `objects.updated_at` (which is stored as ISO-8601).
    struct ClosedDateRange: Equatable {
        var from: Date?
        var to: Date?
    }

    /// Advanced search. Compiles the filter to a single SQL query
    /// against `objects_fts` (and `record_tags` / `objects` via
    /// subquery when needed). Returns the same `Hit` shape as the
    /// free-text overload so call sites can render the two
    /// uniformly.
    ///
    /// **Design notes.**
    /// - Free-text uses the existing FTS5 prefix-match shape, so a
    ///   typed "ad" finds "Adam".
    /// - Tag filtering uses the derived `record_tags` table
    ///   (migration v4) — `.any` is a plain `IN (?, ?, ...)`
    ///   subquery; `.all` is `GROUP BY record_id HAVING COUNT(DISTINCT
    ///   tag_id) = N`. Both run against an indexed table.
    /// - Date filtering subqueries against `objects.updated_at` so
    ///   we don't have to widen the FTS table.
    /// - `excludingTypeIds` always applied (Vault gating). The UI
    ///   passes `schema.vaultTypeIds` here whenever Vault is locked
    ///   or "Include Vault" is unchecked.
    /// - An empty `query` returns matching rows ordered by recency
    ///   (via subquery against `objects.updated_at`) rather than
    ///   FTS rank, since `rank` isn't defined without a MATCH.
    static func search(_ filter: Filter) -> [Hit] {
        // Tag-and-untagged conflict resolution: requiredTagIds wins.
        let untaggedOnly = filter.untaggedOnly && filter.requiredTagIds.isEmpty

        var sql = "SELECT objects_fts.object_id, objects_fts.type_id, objects_fts.title, objects_fts.body FROM objects_fts"
        var clauses: [String] = []
        var args: [DatabaseValueConvertible] = []

        // Free-text MATCH (when non-empty).
        let trimmed = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let tokens = trimmed
                .lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .map { sanitize($0) + "*" }
            let pattern = tokens.joined(separator: " ")
            clauses.append("objects_fts MATCH ?")
            args.append(pattern)
        }

        // Type-scope restriction.
        if let typeIds = filter.typeIds, !typeIds.isEmpty {
            let placeholders = Array(repeating: "?", count: typeIds.count).joined(separator: ", ")
            clauses.append("objects_fts.type_id IN (\(placeholders))")
            args.append(contentsOf: typeIds.sorted())
        }

        // Always-exclude (Vault gating).
        if !filter.excludingTypeIds.isEmpty {
            let placeholders = Array(repeating: "?", count: filter.excludingTypeIds.count).joined(separator: ", ")
            clauses.append("objects_fts.type_id NOT IN (\(placeholders))")
            args.append(contentsOf: filter.excludingTypeIds.sorted())
        }

        // Tag filter — IN-subquery against record_tags.
        if !filter.requiredTagIds.isEmpty {
            let ids = Array(filter.requiredTagIds).sorted()
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
            switch filter.tagMatchMode {
            case .any:
                clauses.append("objects_fts.object_id IN (SELECT record_id FROM record_tags WHERE tag_id IN (\(placeholders)))")
                args.append(contentsOf: ids)
            case .all:
                clauses.append("""
                    objects_fts.object_id IN (
                        SELECT record_id FROM record_tags
                        WHERE tag_id IN (\(placeholders))
                        GROUP BY record_id
                        HAVING COUNT(DISTINCT tag_id) = \(ids.count)
                    )
                    """)
                args.append(contentsOf: ids)
            }
        } else if untaggedOnly {
            clauses.append("objects_fts.object_id NOT IN (SELECT record_id FROM record_tags)")
        }

        // Date range — subquery against objects.updated_at (ISO-8601
        // strings, lexicographically comparable).
        if let range = filter.dateRange, range.from != nil || range.to != nil {
            var dateClauses: [String] = []
            if let from = range.from {
                dateClauses.append("updated_at >= ?")
                args.append(ISO8601DateFormatter().string(from: from))
            }
            if let to = range.to {
                dateClauses.append("updated_at <= ?")
                args.append(ISO8601DateFormatter().string(from: to))
            }
            clauses.append("objects_fts.object_id IN (SELECT id FROM objects WHERE \(dateClauses.joined(separator: " AND ")))")
        }

        if !clauses.isEmpty {
            sql += " WHERE " + clauses.joined(separator: " AND ")
        }

        // Order: FTS rank when MATCH used; updated_at desc otherwise.
        // `rank` is only defined inside a MATCH context, so the
        // empty-query path falls back to a join on `objects` for
        // recency ordering. We do this with a subquery rather than
        // a JOIN so the no-results-from-objects edge case (orphan
        // FTS row) doesn't drop matches silently.
        if !trimmed.isEmpty {
            sql += " ORDER BY rank LIMIT ?"
        } else {
            sql += " ORDER BY (SELECT updated_at FROM objects WHERE id = objects_fts.object_id) DESC LIMIT ?"
        }
        args.append(filter.limit)

        do {
            return try DatabaseService.shared.dbPool.read { db in
                try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args)).map { row in
                    Hit(
                        recordId: row["object_id"],
                        typeId: row["type_id"],
                        title: row["title"],
                        body: row["body"]
                    )
                }
            }
        } catch {
            NSLog("PurpleLife: SearchService.search(filter:) failed — \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Helpers

    /// Strip characters that would confuse FTS5's mini-grammar (quotes,
    /// parens, asterisks already added). Anything non-alphanumeric becomes
    /// whitespace so multi-word inputs still tokenize.
    private static func sanitize(_ token: String) -> String {
        token.map { ($0.isLetter || $0.isNumber) ? $0 : " " }
             .reduce(into: "") { $0.append($1) }
             .components(separatedBy: .whitespaces)
             .filter { !$0.isEmpty }
             .joined(separator: " ")
    }

    /// Title + body strings to feed into the FTS table for one record.
    /// Title gets the primary field's value (or "Untitled"). Body gets
    /// every other text-bearing field — text, longText, url, email,
    /// link, select-label, multi-select-labels, number, date strings —
    /// joined with spaces.
    static func searchableText(for record: ObjectRecord, type: ObjectType) -> (title: String, body: String) {
        let fields = record.fields()
        let title: String = {
            if let key = type.primaryFieldKey,
               let s = fields[key] as? String,
               !s.isEmpty {
                return s
            }
            return "Untitled"
        }()

        var body: [String] = []
        for f in type.fields where f.key != type.primaryFieldKey {
            guard let v = fields[f.key] else { continue }
            switch f.kind {
            case .text, .longText, .url, .email, .link, .select:
                if let s = v as? String, !s.isEmpty { body.append(s) }
            case .richText:
                // richText stores `{ "rtf": "<base64>", "plain": "..." }`.
                // FTS only ever sees the plain mirror — keeping the index
                // unaware of the encoded RTF is what keeps the FTS body
                // genuinely searchable without parsing RTF.
                if let dict = v as? [String: Any],
                   let plain = dict["plain"] as? String,
                   !plain.isEmpty {
                    body.append(plain)
                }
            case .noteLog:
                // Aggregate each entry's plain mirror into the FTS body.
                // Attachment filenames also get indexed — searching for a
                // PDF name should find the entry that has it attached.
                if let dict = v as? [String: Any],
                   let entries = dict["entries"] as? [[String: Any]] {
                    for entry in entries {
                        if let plain = entry["plain"] as? String, !plain.isEmpty {
                            body.append(plain)
                        }
                        if let atts = entry["attachments"] as? [[String: Any]] {
                            for att in atts {
                                if let name = att["filename"] as? String, !name.isEmpty {
                                    body.append(name)
                                }
                            }
                        }
                    }
                }
            case .multiSelect:
                if let arr = v as? [String] { body.append(arr.joined(separator: " ")) }
            case .number:
                if let d = v as? Double { body.append(d.formatted()) }
                if let i = v as? Int    { body.append("\(i)") }
            case .date, .dateTime:
                if let s = v as? String, !s.isEmpty { body.append(s) }
            case .rating, .boolean, .attachment:
                continue
            }
        }
        return (title, body.joined(separator: " "))
    }
}
