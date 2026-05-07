import Foundation
import GRDB

/// Attachment — file payload stored as a BLOB inside the SQLite DB so backups
/// roll up everything in one zip. SHA1 is the on-access integrity check
/// (per spec); MD5 + SHA256 are stored alongside for completeness and shown
/// in the UI. `lastVerifiedAt` / `lastVerifyOk` are bumped by
/// `AttachmentService.verify()`.
struct Attachment: Codable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "attachment"

    var id: String                  // UUID
    var matterId: String            // FK matter.id
    var filename: String
    var sizeBytes: Int64
    var mimeType: String
    var data: Data                  // the BLOB
    var md5: String
    var sha1: String
    var sha256: String
    var addedAt: Date
    var lastVerifiedAt: Date?
    var lastVerifyOk: Bool          // false ⇒ red banner / flag

    enum CodingKeys: String, CodingKey {
        case id, filename, data, md5, sha1, sha256
        case matterId = "matter_id"
        case sizeBytes = "size_bytes"
        case mimeType = "mime_type"
        case addedAt = "added_at"
        case lastVerifiedAt = "last_verified_at"
        case lastVerifyOk = "last_verify_ok"
    }
}
