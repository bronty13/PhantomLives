import Foundation
import GRDB

public struct ClipNote: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    public var id: Int64?
    public var clipId: String
    public var body: String
    public var operatorName: String
    public var createdAt: String
    public var updatedAt: String

    public static let databaseTableName = "clip_notes"

    enum CodingKeys: String, CodingKey {
        case id
        case clipId       = "clip_id"
        case body
        case operatorName = "operator_name"
        case createdAt    = "created_at"
        case updatedAt    = "updated_at"
    }

    public init(
        id: Int64? = nil,
        clipId: String,
        body: String,
        operatorName: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.clipId = clipId
        self.body = body
        self.operatorName = operatorName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
