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
    static func search(_ query: String, limit: Int = 50) -> [Hit] {
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
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT object_id, type_id, title, body
                        FROM objects_fts
                        WHERE objects_fts MATCH ?
                        ORDER BY rank
                        LIMIT ?
                    """,
                    arguments: [pattern, limit]
                ).map { row in
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
