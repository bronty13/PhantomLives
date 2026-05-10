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

    @discardableResult
    static func create(typeId: String, parentId: String? = nil, fields: [String: Any] = [:]) throws -> ObjectRecord {
        let record = ObjectRecord.make(typeId: typeId, parentId: parentId, fields: fields)
        try DatabaseService.shared.insertObject(record)
        if let type = currentSchema?.type(id: typeId) {
            SearchService.upsert(record: record, type: type)
        }
        return record
    }

    static func update(_ record: ObjectRecord, fields: [String: Any]) throws -> ObjectRecord {
        let json = (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        var next = record
        next.fieldsJSON = json
        try DatabaseService.shared.updateObject(next)
        if let type = currentSchema?.type(id: next.typeId) {
            SearchService.upsert(record: next, type: type)
        }
        return next
    }

    static func delete(id: String) throws {
        try DatabaseService.shared.deleteObject(id: id)
        SearchService.delete(recordId: id)
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
}
