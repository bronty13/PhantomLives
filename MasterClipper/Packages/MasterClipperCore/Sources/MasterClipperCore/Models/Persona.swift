import Foundation
import GRDB

public struct Persona: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    public var id: Int64?
    public var code: String
    public var displayName: String
    public var colorHex: String
    public var sortOrder: Int
    public var archived: Bool

    public static let databaseTableName = "personas"

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case displayName = "display_name"
        case colorHex = "color_hex"
        case sortOrder = "sort_order"
        case archived
    }

    public init(
        id: Int64? = nil,
        code: String,
        displayName: String,
        colorHex: String,
        sortOrder: Int,
        archived: Bool
    ) {
        self.id = id
        self.code = code
        self.displayName = displayName
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.archived = archived
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
