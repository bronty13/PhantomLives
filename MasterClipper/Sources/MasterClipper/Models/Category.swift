import Foundation
import GRDB

struct Category: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: Int64?
    var name: String
    var sortOrder: Int
    var archived: Bool

    static let databaseTableName = "categories"

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sortOrder = "sort_order"
        case archived
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
