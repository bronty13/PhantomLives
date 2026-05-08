import Foundation
import GRDB

/// A small checklist item attached to a Matter. Used by the Subtasks tab to
/// break down work without spinning up a full child Matter.
struct Subtask: Codable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "subtask"

    var id: String
    var matterId: String
    var body: String
    var done: Bool
    var sortOrder: Int
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body, done
        case matterId = "matter_id"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }
}
