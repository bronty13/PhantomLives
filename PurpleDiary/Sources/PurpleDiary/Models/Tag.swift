import Foundation
import GRDB

/// A named, colored tag. `rowId` is the autoincrement PK; `id` (for
/// Identifiable) is the unique name. Mirrors Timeliner's Tag shape so the
/// editor / chip UI patterns port directly.
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

/// Join row: entry ↔ tag.
struct EntryTag: Codable, FetchableRecord, PersistableRecord, Hashable {
    var entryId: String
    var tagId: Int64

    static let databaseTableName = "entry_tags"

    enum CodingKeys: String, CodingKey {
        case entryId = "entry_id"
        case tagId = "tag_id"
    }
}
