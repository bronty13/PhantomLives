import Foundation

/// Thin facade over `DatabaseService`. In Phase 2 this gains the schema
/// registry, field-level validation, and the cross-type link table; for
/// Phase 1 it's just enough CRUD to drive the round-trip acceptance test.
@MainActor
enum ObjectEngine {

    @discardableResult
    static func create(typeId: String, parentId: String? = nil, fields: [String: Any] = [:]) throws -> ObjectRecord {
        let record = ObjectRecord.make(typeId: typeId, parentId: parentId, fields: fields)
        try DatabaseService.shared.insertObject(record)
        return record
    }

    static func update(_ record: ObjectRecord, fields: [String: Any]) throws -> ObjectRecord {
        let json = (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        var next = record
        next.fieldsJSON = json
        try DatabaseService.shared.updateObject(next)
        return next
    }

    static func delete(id: String) throws {
        try DatabaseService.shared.deleteObject(id: id)
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
