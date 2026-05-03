import Foundation
import GRDB

struct Persona: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: Int64?
    var code: String
    var displayName: String
    var colorHex: String
    var sortOrder: Int
    var archived: Bool

    static let databaseTableName = "personas"

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case displayName = "display_name"
        case colorHex = "color_hex"
        case sortOrder = "sort_order"
        case archived
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
