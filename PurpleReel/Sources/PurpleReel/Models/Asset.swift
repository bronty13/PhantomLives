import Foundation
import GRDB

struct Asset: Codable, Identifiable, Equatable, Hashable, FetchableRecord, PersistableRecord {
    /// GRDB autoincrement column. Optional because pre-insert it's nil;
    /// the Identifiable view layer uses `path` instead (see Table init).
    var rowId: Int64?
    var path: String

    var id: String { path }
    var filename: String
    var sizeBytes: Int64
    var modifiedAt: Date
    var codec: String?
    var widthPx: Int?
    var heightPx: Int?
    var durationSeconds: Double?
    var frameRate: Double?
    var sha1: String?
    var addedAt: Date
    /// Audio codec four-CC (e.g. "aac ", "mp4a", "alac", "pcm "). Read
    /// at scan time from the asset's first audio track's
    /// `formatDescription`. Nil for image / video-only assets.
    var audioCodec: String?
    /// "Date recorded" — `AVAsset.creationDate.dateValue`. Reflects the
    /// camera-set recording time when the file's container carries it
    /// (most prosumer cameras + iPhone do). Nil for assets where the
    /// container has no creation-date metadata.
    var recordedAt: Date?
    /// Filesystem birth time (BTime) for the file at scan time —
    /// `URLResourceKey.creationDateKey`. Distinct from
    /// `modifiedAt` (last-write) and `recordedAt` (camera/container
    /// metadata). Nil on volumes where the FS doesn't carry one.
    /// Default = nil keeps the old memberwise initializer's
    /// call-site compatible.
    var createdAt: Date? = nil

    static let databaseTableName = "asset"

    // Map the GRDB primary key column (named `id` in SQL) to our
    // `rowId` Swift property; the Swift `id` computed property is
    // for SwiftUI Identifiable, not the database.
    enum CodingKeys: String, CodingKey {
        case rowId = "id"
        case path, filename, sizeBytes, modifiedAt, codec, widthPx, heightPx
        case durationSeconds, frameRate, sha1, addedAt
        case audioCodec, recordedAt, createdAt
    }

    enum Columns {
        static let rowId = Column(CodingKeys.rowId)
        static let path = Column(CodingKeys.path)
        static let filename = Column(CodingKeys.filename)
        static let modifiedAt = Column(CodingKeys.modifiedAt)
    }
}

enum AssetKind: String, CaseIterable, Identifiable {
    case video, audio, image, other
    var id: String { rawValue }

    static func from(extension ext: String) -> AssetKind {
        switch ext.lowercased() {
        case "mov", "mp4", "m4v", "hevc", "h264", "prores": return .video
        case "wav", "aif", "aiff", "mp3", "m4a", "flac": return .audio
        case "jpg", "jpeg", "png", "heic", "tif", "tiff", "raw", "dng": return .image
        default: return .other
        }
    }
}
