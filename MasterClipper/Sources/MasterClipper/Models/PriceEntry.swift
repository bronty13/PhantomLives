import Foundation
import GRDB

struct PriceEntry: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: Int64?
    var label: String
    var priceCents: Int
    var notes: String

    static let databaseTableName = "prices"

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case priceCents = "price_cents"
        case notes
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
