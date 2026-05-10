import Foundation

/// Phase 3 query executor. Runs a `SavedQuery` against the object engine
/// and returns matching records. Single-pass per query — Phase 3's row
/// counts are small enough that we can fetch the candidate set, filter
/// in Swift, and sort in Swift without bothering with FTS5 or the
/// generated SQL we'd need for richer predicates. The interface stays
/// the same when we swap to a real query compiler later.
@MainActor
enum QueryRunner {

    static func run(_ query: SavedQuery, schema: SchemaRegistry) -> [(record: ObjectRecord, type: ObjectType)] {
        let candidates: [ObjectRecord]
        do {
            if let typeId = query.typeId {
                candidates = try ObjectEngine.fetch(typeId: typeId)
            } else {
                candidates = try ObjectEngine.fetchAll()
            }
        } catch {
            NSLog("PurpleLife: QueryRunner fetch failed — \(error.localizedDescription)")
            return []
        }

        let filtered = candidates.filter { matches(query: query, record: $0) }

        // Pair with type. Records whose type was deleted from the schema
        // are dropped — we can't render them without their FieldDef list.
        let paired: [(ObjectRecord, ObjectType)] = filtered.compactMap { record in
            schema.type(id: record.typeId).map { (record, $0) }
        }

        // Sort. Default key is updated_at (already ISO-8601 sortable).
        let sorted = paired.sorted { a, b in
            let aV = sortValue(for: a.0, key: query.sortFieldKey)
            let bV = sortValue(for: b.0, key: query.sortFieldKey)
            return query.descending ? aV > bV : aV < bV
        }

        let limit = query.limit > 0 ? query.limit : Int.max
        return Array(sorted.prefix(limit))
    }

    // MARK: - Filtering

    private static func matches(query: SavedQuery, record: ObjectRecord) -> Bool {
        // Date-range case keys off `updated_at`, not a per-field key.
        if case .withinDays(let days) = query.filterValue {
            guard let updated = ISO8601DateFormatter().date(from: record.updatedAt) else { return false }
            let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
            return updated >= cutoff
        }

        guard let key = query.filterFieldKey, let v = query.filterValue else { return true }
        let value = record.fields()[key]
        switch v {
        case .string(let target):
            return (value as? String) == target
        case .bool(let target):
            return (value as? Bool) == target
        case .nonEmpty:
            if let s = value as? String { return !s.isEmpty }
            if let arr = value as? [Any] { return !arr.isEmpty }
            return value != nil
        case .withinDays:
            return true   // handled above
        }
    }

    // MARK: - Sorting

    /// Comparable representation of a record's value for a given sort key.
    /// Returns the empty string when the field is missing — sorting
    /// stable-ifies on `updated_at` desc by default which is what we
    /// want.
    private static func sortValue(for record: ObjectRecord, key: String?) -> String {
        guard let key, !key.isEmpty else { return record.updatedAt }
        if let s = record.fields()[key] as? String { return s }
        if let i = record.fields()[key] as? Int    { return String(format: "%020d", i) }
        if let d = record.fields()[key] as? Double { return String(format: "%030.10f", d) }
        return record.updatedAt
    }
}

