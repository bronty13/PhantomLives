import Foundation
import GRDB

/// Per-file metadata captured for the component `.mov` files that make up a
/// clip's source folder. One row per video file (`1.mov`, `2.mov`, …) keyed
/// by `clip_id` + `position`. Hashes are computed once and persisted so the
/// app can later prove a file hasn't drifted on disk.
struct ClipSegment: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: Int64?
    var clipId: String
    var position: Int                   // 1-based: 1, 2, 3 …
    var filename: String                // "1.mov" after Fix order; original name otherwise
    var creationDate: String            // max-precision ctime, "yyyy-MM-dd HH:mm:ss.SSSSSS +0000"
    var sizeBytes: Int64?
    var md5: String                     // hex digest; empty until hashed
    var sha1: String
    var sha256: String
    var hashedAt: String                // ISO timestamp; empty until first hash
    var createdAt: String
    var updatedAt: String

    static let databaseTableName = "clip_segments"

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

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
