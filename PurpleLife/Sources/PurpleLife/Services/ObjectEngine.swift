import Foundation

/// Thin facade over `DatabaseService`. Phase 2 expansion: every mutation
/// also keeps the FTS5 search index in sync via `SearchService`.
@MainActor
enum ObjectEngine {

    /// Set by `AppState` at launch — gives the engine the schema it needs
    /// to build searchable text for the FTS index. Optional so tests that
    /// hit `ObjectEngine` without a wired SchemaRegistry still work; they
    /// just skip the FTS hook.
    static var currentSchema: SchemaRegistry?

    /// Set by `AppState` at launch — engine fans every mutation out to
    /// CloudKit. Optional so tests can run without a sync service wired.
    /// The push is fire-and-forget Task; local writes complete first.
    static var sync: CloudKitSyncService?

    @discardableResult
    static func create(typeId: String, parentId: String? = nil, fields: [String: Any] = [:]) throws -> ObjectRecord {
        let record = ObjectRecord.make(typeId: typeId, parentId: parentId, fields: fields)
        try DatabaseService.shared.insertObject(record)
        if let type = currentSchema?.type(id: typeId) {
            SearchService.upsert(record: record, type: type)
        }
        if let sync {
            Task { await sync.push(record: record) }
        }
        return record
    }

    static func update(_ record: ObjectRecord, fields: [String: Any]) throws -> ObjectRecord {
        // Defensive merge — preserve any keys present in the existing
        // JSON that the caller didn't include. This is the
        // schema-versioning safety net: if a peer running a stale
        // schema receives a record carrying a field it doesn't know
        // about, then the user edits that record locally, the form
        // only sends back the fields the local schema defines. Without
        // this merge, the unknown field would be silently dropped.
        // The same intent is documented in
        // `SchemaRegistry.removeField` — schema deletions leave their
        // field data in records untouched. Schema additions sync via
        // CloudKit so eventually the peer learns about the field, but
        // the merge closes the window between record-arriving and
        // schema-arriving.
        var merged = record.fields()
        for (k, v) in fields { merged[k] = v }
        let json = (try? JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        var next = record
        next.fieldsJSON = json
        try DatabaseService.shared.updateObject(next)
        if let type = currentSchema?.type(id: next.typeId) {
            SearchService.upsert(record: next, type: type)
        }
        // Re-fetch to capture the bumped updated_at that DatabaseService.update
        // stamped — push() compares timestamps for LWW.
        let pushable = (try? DatabaseService.shared.fetchObject(id: next.id)) ?? next
        if let sync {
            Task { await sync.push(record: pushable) }
        }
        return pushable
    }

    static func delete(id: String) throws {
        try DatabaseService.shared.deleteObject(id: id)
        SearchService.delete(recordId: id)
        if let sync {
            Task { await sync.pushDelete(recordId: id) }
        }
    }

    static func fetch(id: String) throws -> ObjectRecord? {
        try DatabaseService.shared.fetchObject(id: id)
    }

    static func fetchAll() throws -> [ObjectRecord] {
        try DatabaseService.shared.fetchAllObjects()
    }

    static func fetch(typeId: String) throws -> [ObjectRecord] {
        try DatabaseService.shared.fetchObjects(typeId: typeId)
    }

    static func count() throws -> Int {
        try DatabaseService.shared.objectCount()
    }

    // MARK: - Link resolution

    /// Returns the title (primary-field value or "Untitled") of the
    /// record referenced by a `.link` field's stored id, or `nil` if
    /// the id doesn't resolve. Used by both `FieldDisplay` (read-only
    /// rendering) and `LinkFieldEditor` (the popover picker label).
    static func resolveLinkedTitle(recordId: String) -> String? {
        guard !recordId.isEmpty,
              let schema = currentSchema,
              let r = try? DatabaseService.shared.fetchObject(id: recordId),
              let type = schema.type(id: r.typeId) else { return nil }
        return FieldDisplay.title(of: r, in: type)
    }

    /// All records across every type, with their resolved type — used
    /// by the cross-type link picker. Sorted by `updated_at` desc so
    /// recent things bubble to the top.
    static func allWithTypes(schema: SchemaRegistry) throws -> [(record: ObjectRecord, type: ObjectType)] {
        try DatabaseService.shared.fetchAllObjects().compactMap { r in
            guard let type = schema.type(id: r.typeId) else { return nil }
            return (r, type)
        }
    }
}
