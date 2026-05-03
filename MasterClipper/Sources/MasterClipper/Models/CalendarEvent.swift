import Foundation
import GRDB

struct CalendarEvent: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: Int64?
    var date: String                            // "YYYY-MM-DD"
    var personaCode: String
    var clipId: String?
    var title: String
    var notes: String
    var createdAt: String
    var updatedAt: String

    static let databaseTableName = "calendar_events"

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case personaCode = "persona_code"
        case clipId = "clip_id"
        case title
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
