import Foundation
import GRDB

/// One row per timer session. `seconds` is denormalized so weekly aggregations
/// can sum without parsing the start/end timestamps. `endedAt` is null while
/// the timer is still running (we persist the active timer on quit).
struct TimeEntry: Codable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "time_entry"

    var id: String                  // UUID
    var matterId: String
    var startedAt: Date
    var endedAt: Date?
    var seconds: Int                // 0 while running; finalized on stop
    var note: String

    enum CodingKeys: String, CodingKey {
        case id, seconds, note
        case matterId = "matter_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}
