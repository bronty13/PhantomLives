import Foundation
import GRDB

/// Polymorphic attachment record. A single `attachments` table stores files
/// linked to any parent kind (case, event, person). The actual file bytes
/// live in the `data` BLOB so they're carried automatically by the
/// database backup zip.
///
/// Thumbnails (image-only) are stored alongside as a separate `thumbnailData`
/// BLOB so list views can render previews without paging the full asset
/// into memory.
struct Attachment: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: String                  // UUID
    var parentType: String          // AttachmentParent.rawValue
    var parentId: String            // case.id / event.id / person.id
    var filename: String
    var mimeType: String
    var sizeBytes: Int64
    var data: Data
    var thumbnailData: Data?
    var position: Int               // user-controlled order within parent
    var createdAt: String

    static let databaseTableName = "attachments"

    enum CodingKeys: String, CodingKey {
        case id
        case parentType = "parent_type"
        case parentId = "parent_id"
        case filename
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case data
        case thumbnailData = "thumbnail_data"
        case position
        case createdAt = "created_at"
    }

    var parentEnum: AttachmentParent {
        AttachmentParent(rawValue: parentType) ?? .event
    }

    var isImage: Bool { mimeType.hasPrefix("image/") }
    var isPDF: Bool { mimeType == "application/pdf" }
}

enum AttachmentParent: String, Codable, CaseIterable, Hashable {
    case caseRecord = "case"
    case event
    case person

    var label: String {
        switch self {
        case .caseRecord: return "Case"
        case .event:      return "Event"
        case .person:     return "Person"
        }
    }
}
