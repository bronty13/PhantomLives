import Foundation
import GRDB

/// Read-only queries used by both the macOS app (against its live DatabasePool)
/// and the iOS app (against a read-only DatabaseQueue opened on the iCloud
/// snapshot). Every function takes a `DatabaseReader` so the same code path
/// works on either side.
public enum ClipQueries {

    public static func fetchAllClips(includeArchived: Bool = false, in reader: any DatabaseReader) throws -> [Clip] {
        try reader.read { db in
            var q = Clip.order(Column("created_at").desc)
            if !includeArchived { q = q.filter(Column("archived") == false) }
            return try q.fetchAll(db)
        }
    }

    public static func fetchClip(id: String, in reader: any DatabaseReader) throws -> Clip? {
        try reader.read { db in try Clip.fetchOne(db, key: id) }
    }

    public static func fetchPersonas(includeArchived: Bool = false, in reader: any DatabaseReader) throws -> [Persona] {
        try reader.read { db in
            var q = Persona.order(Column("sort_order").asc, Column("code").asc)
            if !includeArchived { q = q.filter(Column("archived") == false) }
            return try q.fetchAll(db)
        }
    }

    public static func fetchSites(includeArchived: Bool = false, in reader: any DatabaseReader) throws -> [Site] {
        try reader.read { db in
            var q = Site.order(Column("sort_order").asc, Column("code").asc)
            if !includeArchived { q = q.filter(Column("archived") == false) }
            return try q.fetchAll(db)
        }
    }

    public static func fetchCategories(includeArchived: Bool = false, in reader: any DatabaseReader) throws -> [ClipCategory] {
        try reader.read { db in
            var q = ClipCategory.order(Column("sort_order").asc, Column("name").asc)
            if !includeArchived { q = q.filter(Column("archived") == false) }
            return try q.fetchAll(db)
        }
    }

    public static func fetchClipNotes(clipId: String, in reader: any DatabaseReader) throws -> [ClipNote] {
        try reader.read { db in
            try ClipNote
                .filter(Column("clip_id") == clipId)
                .order(Column("created_at").asc, Column("id").asc)
                .fetchAll(db)
        }
    }

    public static func fetchPostings(forClip clipId: String, in reader: any DatabaseReader) throws -> [ClipPosting] {
        try reader.read { db in
            try ClipPosting
                .filter(Column("clip_id") == clipId)
                .fetchAll(db)
        }
    }

    /// Categories attached to a clip, joined through `clip_categories`. Ordered
    /// by the position column the writer maintains on the join table.
    public static func fetchCategoriesForClip(clipId: String, in reader: any DatabaseReader) throws -> [ClipCategory] {
        try reader.read { db in
            try ClipCategory.fetchAll(db, sql: """
                SELECT c.* FROM categories c
                JOIN clip_categories cc ON cc.category_id = c.id
                WHERE cc.clip_id = ?
                ORDER BY cc.position ASC
                """, arguments: [clipId])
        }
    }

    // MARK: - Full-text search

    /// True if this database has the `clips_fts` virtual table populated by
    /// SnapshotPublisher. Only snapshots have it; the live macOS DB does not.
    public static func hasFTS(in reader: any DatabaseReader) -> Bool {
        (try? reader.read { db in
            try Bool.fetchOne(db,
                sql: "SELECT 1 FROM sqlite_master WHERE type='table' AND name='clips_fts'") ?? false
        }) ?? false
    }

    /// Tokenised FTS5 search across title / descriptions / keywords /
    /// performers / transcript. Returns matched `Clip` rows in BM25 rank order
    /// (best match first). Empty query returns []. Caller is responsible for
    /// gating with `hasFTS(in:)`.
    ///
    /// User input is sanitised: punctuation that has special meaning in FTS5
    /// (parens, quotes, asterisks) is stripped, then each token is suffixed
    /// with `*` for prefix matching so typing "redhe" finds "redhead".
    public static func searchFTS(query: String, in reader: any DatabaseReader) throws -> [Clip] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tokens = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .map { sanitiseFTSToken(String($0)) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }

        // AND across tokens; prefix-match each so partial words score.
        let matchExpr = tokens.map { "\($0)*" }.joined(separator: " ")

        return try reader.read { db in
            try Clip.fetchAll(db, sql: """
                SELECT c.* FROM clips c
                JOIN clips_fts f ON f.rowid = c.rowid
                WHERE clips_fts MATCH ?
                ORDER BY bm25(clips_fts)
                """, arguments: [matchExpr])
        }
    }

    private static let ftsReservedCharacters = CharacterSet(charactersIn: "\"'*():-")

    private static func sanitiseFTSToken(_ raw: String) -> String {
        raw.unicodeScalars
            .filter { !ftsReservedCharacters.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
    }
}
