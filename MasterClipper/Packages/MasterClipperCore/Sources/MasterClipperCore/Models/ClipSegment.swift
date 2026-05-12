import Foundation
import GRDB

public struct ClipSegment: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    public var id: Int64?
    public var clipId: String
    public var position: Int
    public var filename: String
    public var creationDate: String
    public var sizeBytes: Int64?
    public var md5: String
    public var sha1: String
    public var sha256: String
    public var hashedAt: String
    public var createdAt: String
    public var updatedAt: String

    public static let databaseTableName = "clip_segments"

    enum CodingKeys: String, CodingKey {
        case id
        case clipId = "clip_id"
        case position
        case filename
        case creationDate = "creation_date"
        case sizeBytes    = "size_bytes"
        case md5
        case sha1
        case sha256
        case hashedAt     = "hashed_at"
        case createdAt    = "created_at"
        case updatedAt    = "updated_at"
    }

    public init(
        id: Int64? = nil,
        clipId: String,
        position: Int,
        filename: String,
        creationDate: String,
        sizeBytes: Int64? = nil,
        md5: String,
        sha1: String,
        sha256: String,
        hashedAt: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.clipId = clipId
        self.position = position
        self.filename = filename
        self.creationDate = creationDate
        self.sizeBytes = sizeBytes
        self.md5 = md5
        self.sha1 = sha1
        self.sha256 = sha256
        self.hashedAt = hashedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
