import Foundation
import GRDB

/// A file attached to an entry — currently always a photo imported from the
/// Photos library ("auto-assembled day"). The bytes live in the `data` BLOB
/// *inside* `diary.sqlite`, so they inherit the database's SQLCipher
/// encryption at rest (and ride along in the backup zip) with no extra crypto.
/// A small JPEG `thumbnailData` is stored alongside so the editor's photo strip
/// renders without paging full images into memory.
///
/// `sourceAssetId` is the originating `PHAsset.localIdentifier`, used to avoid
/// importing the same photo onto the same entry twice.
struct Attachment: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: String                  // UUID
    var entryId: String
    var kind: String                // "photo" for now; reserved for video/audio/file later
    var filename: String
    var mimeType: String
    var sizeBytes: Int64
    var width: Int
    var height: Int
    var data: Data
    var thumbnailData: Data?
    var sourceAssetId: String?
    var createdAt: String

    static let databaseTableName = "attachments"

    enum CodingKeys: String, CodingKey {
        case id
        case entryId = "entry_id"
        case kind
        case filename
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case width
        case height
        case data
        case thumbnailData = "thumbnail_data"
        case sourceAssetId = "source_asset_id"
        case createdAt = "created_at"
    }

    var isImage: Bool { mimeType.hasPrefix("image/") }
    var isVideo: Bool { kind == "video" || mimeType.hasPrefix("video/") }
    var isAudio: Bool { kind == "audio" || mimeType.hasPrefix("audio/") }
    var isPDF: Bool { kind == "pdf" || mimeType == "application/pdf" }
    /// A generic, non-previewable file attachment.
    var isFile: Bool { kind == "file" }
}

/// Lightweight projection for the editor's photo strip: identity + thumbnail +
/// dimensions + media kind, without paging the full-resolution `data` BLOB into
/// memory. `kind`/`mimeType` let the strip badge videos and the viewer pick
/// image-vs-player without loading the bytes.
struct AttachmentThumb: Identifiable, Hashable, FetchableRecord {
    var id: String
    var entryId: String
    var kind: String
    var mimeType: String
    var filename: String
    var thumbnailData: Data?
    var width: Int
    var height: Int

    init(row: Row) {
        id = row["id"]
        entryId = row["entry_id"]
        kind = row["kind"]
        mimeType = row["mime_type"]
        filename = row["filename"]
        thumbnailData = row["thumbnail_data"]
        width = row["width"]
        height = row["height"]
    }

    var isVideo: Bool { kind == "video" || mimeType.hasPrefix("video/") }
    var isAudio: Bool { kind == "audio" || mimeType.hasPrefix("audio/") }
    var isPDF: Bool { kind == "pdf" || mimeType == "application/pdf" }
    var isFile: Bool { kind == "file" }
}
