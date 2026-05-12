import Foundation
import GRDB

public struct CalendarEvent: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    public var id: Int64?
    public var date: String
    public var personaCode: String
    public var clipId: String?
    public var title: String
    public var notes: String
    public var createdAt: String
    public var updatedAt: String

    public static let databaseTableName = "calendar_events"

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

    public init(
        id: Int64? = nil,
        date: String,
        personaCode: String,
        clipId: String? = nil,
        title: String,
        notes: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.date = date
        self.personaCode = personaCode
        self.clipId = clipId
        self.title = title
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
