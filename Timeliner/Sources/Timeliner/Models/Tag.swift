import Foundation
import GRDB

struct Tag: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var rowId: Int64?
    var name: String
    var colorHex: String

    var id: String { name }

    static let databaseTableName = "tags"

    enum CodingKeys: String, CodingKey {
        case rowId = "id"
        case name
        case colorHex = "color_hex"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        rowId = inserted.rowID
    }
}

struct EventTag: Codable, FetchableRecord, PersistableRecord, Hashable {
    var eventId: String
    var tagId: Int64

    static let databaseTableName = "event_tags"

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case tagId = "tag_id"
    }

    static let event = belongsTo(Event.self, using: ForeignKey(["event_id"], to: ["id"]))
    static let tag   = belongsTo(Tag.self,   using: ForeignKey(["tag_id"],   to: ["id"]))
}
