import Foundation
import GRDB

/// One row in the `objects` table. Storage shape per `PLAN.md` § Locked
/// decisions: typed columns for the things every object has plus a JSON
/// blob carrying the type-specific fields. Phase 1 holds plaintext JSON
/// locally; Phase 4 round-trips that same blob through
/// `CKRecord.encryptedValues` for E2E encryption in the cloud.
struct ObjectRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    var id: String
    var typeId: String
    var parentId: String?
    var fieldsJSON: String
    var createdAt: String   // ISO-8601
    var updatedAt: String   // ISO-8601

    static var databaseTableName: String { "objects" }

    enum CodingKeys: String, CodingKey {
        case id
        case typeId    = "type_id"
        case parentId  = "parent_id"
        case fieldsJSON = "fields_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Convenience constructor — generates an id and stamps timestamps.
    static func make(typeId: String, parentId: String? = nil, fields: [String: Any] = [:]) -> ObjectRecord {
        let now = ISO8601DateFormatter().string(from: Date())
        let json = (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return ObjectRecord(
            id: UUID().uuidString,
            typeId: typeId,
            parentId: parentId,
            fieldsJSON: json,
            createdAt: now,
            updatedAt: now
        )
    }

    /// Decode the JSON blob into a Swift dictionary. Returns `[:]` on any
    /// decode failure rather than throwing — the column is meant to be
    /// permissive at the storage layer; type-level field validation lives
    /// in `SchemaRegistry` (Phase 2).
    func fields() -> [String: Any] {
        guard let data = fieldsJSON.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [:] }
        return dict
    }
}
