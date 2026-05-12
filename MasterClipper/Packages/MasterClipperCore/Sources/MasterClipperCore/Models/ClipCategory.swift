import Foundation
import GRDB

public struct ClipCategory: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    public var id: Int64?
    public var name: String
    public var sortOrder: Int
    public var archived: Bool

    public static let databaseTableName = "categories"

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sortOrder = "sort_order"
        case archived
    }

    public init(id: Int64?, name: String, sortOrder: Int, archived: Bool) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.archived = archived
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
