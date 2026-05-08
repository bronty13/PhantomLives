import Foundation
import GRDB

/// One row per change to a Matter. Append-only — emitted by AppState when a
/// tracked field changes (status, priority, type, title, tags, soft-delete /
/// restore). Surfaced in the History tab.
struct AuditEvent: Codable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "audit_event"

    var id: String
    var matterId: String
    var ts: Date
    var kind: String        // "status" | "priority" | "type" | "title" | "tag" | "created" | "deleted" | "restored"
    var beforeValue: String
    var afterValue: String

    enum CodingKeys: String, CodingKey {
        case id, ts, kind
        case matterId = "matter_id"
        case beforeValue = "before_value"
        case afterValue = "after_value"
    }
}
