import Foundation
import GRDB

/// One row in the `attachments` table. The on-disk file at
/// `~/Library/Application Support/PurpleLife/attachments/<sha256>.<ext>`
/// is the source of truth for content; this row is metadata only.
/// Multiple `Attachment` rows can share a `sha256` — content-addressing
/// gives us free de-duplication when the same file is attached to
/// multiple objects.
struct Attachment: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    var id: String
    var parentObjectId: String
    var fieldKey: String
    var sha256: String
    var filename: String
    var mimeType: String
    var sizeBytes: Int64
    var createdAt: String   // ISO-8601

    static var databaseTableName: String { "attachments" }

    enum CodingKeys: String, CodingKey {
        case id
        case parentObjectId = "parent_object_id"
        case fieldKey       = "field_key"
        case sha256
        case filename
        case mimeType       = "mime_type"
        case sizeBytes      = "size_bytes"
        case createdAt      = "created_at"
    }
}
