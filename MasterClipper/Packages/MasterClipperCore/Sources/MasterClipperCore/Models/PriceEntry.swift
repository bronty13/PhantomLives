import Foundation
import GRDB

public struct PriceEntry: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    public var id: Int64?
    public var label: String
    public var priceCents: Int
    public var notes: String

    public static let databaseTableName = "prices"

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case priceCents = "price_cents"
        case notes
    }

    public init(id: Int64?, label: String, priceCents: Int, notes: String) {
        self.id = id
        self.label = label
        self.priceCents = priceCents
        self.notes = notes
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
