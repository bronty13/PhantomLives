import Foundation

/// User-defined tag in the cross-cutting `TagVocabulary`. Distinct from
/// per-type `.multiSelect` fields named "Tags" — a `TagDef` applies to
/// any record of any type, queried via the reserved `_tags` key inside
/// `ObjectRecord.fieldsJSON`.
///
/// Source of truth lives in `AppSettings.tagVocabulary`; the derived
/// `record_tags` table (migration v4) mirrors per-record tag membership
/// for fast SQL filtering and is maintained by `ObjectEngine` on every
/// mutation — same pattern as the FTS index. The implicit `_tags`
/// array of tag ids inside each record's `fields_json` is the per-record
/// source of truth; the index is rebuilt from it on launch via
/// `TagService.reindexAll()`.
///
/// `updatedAt` is reserved for forthcoming CloudKit LWW sync of the
/// vocabulary (parallel to `ObjectType.updatedAt`); Increment 1 stores
/// the vocabulary locally only.
struct TagDef: Codable, Identifiable, Hashable {
    var id: String              // stable UUID; never reused after delete
    var name: String            // display label; case-insensitive unique within vocabulary
    var colorHex: String?       // optional accent color (hex with #); nil → falls back to neutral
    var createdAt: String       // ISO-8601
    var updatedAt: String       // ISO-8601 — bumped on every vocabulary mutation

    static func make(name: String, colorHex: String? = nil) -> TagDef {
        let now = isoNow()
        return TagDef(
            id: UUID().uuidString,
            name: name,
            colorHex: colorHex,
            createdAt: now,
            updatedAt: now
        )
    }

    /// Fractional-second ISO-8601 stamp — shared between `make()`
    /// and `TagService` mutations so every timestamp in the
    /// vocabulary uses the same format and lexicographic comparison
    /// behaves correctly under LWW. Plain second-precision strings
    /// would sort *after* fractional ones for the same second
    /// (because `Z` > `.`), breaking the comparison.
    static func isoNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    /// Reserved storage key inside `ObjectRecord.fieldsJSON` that holds
    /// a record's tag ids. `FieldDef.slugify` cannot produce a value
    /// starting with `_` (it suppresses leading separators), so the
    /// only ways to collide are a hand-rolled `FieldDef.make(key:)`
    /// or a JSON import that bypasses slugify — both are documented
    /// as forbidden.
    static let recordKey = "_tags"
}
