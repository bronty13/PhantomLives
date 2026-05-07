import Foundation
import GRDB

/// A timestamped note entry on a Matter (the per-row log; this is in addition
/// to the long-form `notes_md` field on the Matter itself).
struct Note: Codable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "note"

    var id: String                  // UUID
    var matterId: String
    var bodyMd: String
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case matterId = "matter_id"
        case bodyMd = "body_md"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
