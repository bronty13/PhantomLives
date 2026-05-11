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

    /// Set by Records / Detail views as they appear, threaded through
    /// from SwiftUI's `@Environment(\.undoManager)`. Each mutation
    /// registers its inverse so ⌘Z (and ⇧⌘Z) round-trip naturally
    /// through the macOS Edit menu. Optional — tests / non-UI callers
    /// just skip the registration.
    static var undoManager: UndoManager?

    /// Sentinel target for undo registration. NSUndoManager keys
    /// undoables by an `AnyObject` target; an enum can't be a target,
    /// so we use a shared NSObject. Lets a future call to
    /// `removeAllActions(withTarget:)` scope cleanup if needed.
    private static let undoTarget = NSObject()

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
        // Undo for a create is a delete by id. When the user invokes
        // undo, `delete()` will register its own inverse (a restore
        // from snapshot), which NSUndoManager promotes to redo while
        // an undo is in flight.
        registerUndo(name: "Create record") {
            try? delete(id: record.id)
        }
        return record
    }

    static func update(_ record: ObjectRecord, fields: [String: Any]) throws -> ObjectRecord {
        // Snapshot the prior fields BEFORE applying the merge so undo
        // can restore them. Use the on-disk record (not the parameter
        // — the caller's `record` may already reflect optimistic UI
        // state) for the snapshot.
        let snapshot = (try? DatabaseService.shared.fetchObject(id: record.id))?.fields() ?? record.fields()

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
        // Undo for an update restores the pre-update fields. Going
        // back through `update()` re-fans-out FTS + sync and registers
        // the inverse (which becomes redo while undo is running).
        let recordId = next.id
        registerUndo(name: "Edit record") {
            guard let current = try? DatabaseService.shared.fetchObject(id: recordId) else { return }
            _ = try? update(current, fields: snapshot)
        }
        return pushable
    }

    static func delete(id: String) throws {
        // Snapshot before deletion so undo can restore the row at its
        // original id (preserving any link references from other
        // records that point to it).
        let snapshot = try? DatabaseService.shared.fetchObject(id: id)
        try DatabaseService.shared.deleteObject(id: id)
        SearchService.delete(recordId: id)
        if let sync {
            Task { await sync.pushDelete(recordId: id) }
        }
        if let snapshot {
            registerUndo(name: "Delete record") {
                _ = try? restore(snapshot)
            }
        }
    }

    /// Re-insert a record snapshot at its original id, fanning out to
    /// FTS + sync the same way `create` does. Public so undo of a
    /// delete preserves the id (and therefore inbound `link` field
    /// references from other records).
    @discardableResult
    static func restore(_ record: ObjectRecord) throws -> ObjectRecord {
        try DatabaseService.shared.insertObject(record)
        if let type = currentSchema?.type(id: record.typeId) {
            SearchService.upsert(record: record, type: type)
        }
        if let sync {
            Task { await sync.push(record: record) }
        }
        // Inverse of restore is delete — registers the redo path when
        // we're called from an undo handler.
        registerUndo(name: "Delete record") {
            try? delete(id: record.id)
        }
        return record
    }

    // MARK: - Undo helpers

    /// Wrap NSUndoManager's `registerUndo(withTarget:handler:)` so the
    /// mutation methods don't have to repeat the guard / target /
    /// action-name boilerplate. `handler` runs synchronously on the
    /// main actor — NSUndoManager dispatches on the calling thread,
    /// which is always the main thread for the SwiftUI
    /// environment-injected manager (and for our tests, which call
    /// `undo()` from the test method's MainActor context). A `Task`
    /// hop here would defer execution past the caller's next
    /// statement, which breaks the synchronous "undo, then assert"
    /// pattern tests rely on.
    private static func registerUndo(name: String, _ handler: @escaping @MainActor () -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: undoTarget) { _ in
            MainActor.assumeIsolated { handler() }
        }
        undoManager.setActionName(name)
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

    /// Reverse of a `.link` field — find every record that points TO
    /// the given `recordId` via any of its type's `.link` fields.
    /// Powers the "Linked from" inspector rail in the detail view.
    ///
    /// O(N · F) over all records and their link fields. Fine for a
    /// personal-scale Life OS (hundreds to low-thousands of records);
    /// if it ever becomes slow, a dedicated `links` index table or
    /// an in-memory cache built from the FTS reindex pass would close
    /// the gap. Not worth the complexity until a real user feels it.
    static func recordsLinkingTo(recordId: String, schema: SchemaRegistry) throws -> [(record: ObjectRecord, type: ObjectType)] {
        guard !recordId.isEmpty else { return [] }
        var results: [(record: ObjectRecord, type: ObjectType)] = []
        for record in try DatabaseService.shared.fetchAllObjects() {
            guard record.id != recordId,
                  let type = schema.type(id: record.typeId) else { continue }
            let fields = record.fields()
            for fieldDef in type.fields where fieldDef.kind == .link {
                if let linked = fields[fieldDef.key] as? String, linked == recordId {
                    results.append((record, type))
                    break
                }
            }
        }
        return results
    }
}
