import Foundation
import GRDB

public struct ExclusionReason: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    public var id: Int64?
    public var label: String
    public var sortOrder: Int
    public var archived: Bool

    public static let databaseTableName = "exclusion_reasons"

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case sortOrder = "sort_order"
        case archived
    }

    public init(id: Int64?, label: String, sortOrder: Int, archived: Bool) {
        self.id = id
        self.label = label
        self.sortOrder = sortOrder
        self.archived = archived
    }
}
