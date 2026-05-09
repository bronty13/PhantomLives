import Foundation
import GRDB

/// GRDB record for the `files` table. Phase 1 stores just enough to seed the cache: the
/// path, size, mtime, type, and content hash. Perceptual hashes (Phase 2+) and EXIF
/// metadata (Phase 4+) live in separate tables that join on `id`.
public struct FileRecord: Codable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "files"

    public var id: Int64?
    public var path: String
    public var sizeBytes: Int64
    public var mtimeUnix: Int64
    public var fileType: String          // "photo" | "video" | "other"
    public var format: String            // lowercase extension
    public var contentHash: Data?        // SHA256 (Phase 1) or BLAKE3 (later) — opaque blob
    public var lastIndexedUnix: Int64

    public init(
        id: Int64? = nil,
        path: String,
        sizeBytes: Int64,
        mtimeUnix: Int64,
        fileType: String,
        format: String,
        contentHash: Data? = nil,
        lastIndexedUnix: Int64
    ) {
        self.id = id
        self.path = path
        self.sizeBytes = sizeBytes
        self.mtimeUnix = mtimeUnix
        self.fileType = fileType
        self.format = format
        self.contentHash = contentHash
        self.lastIndexedUnix = lastIndexedUnix
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Per-file perceptual fingerprint. Stored 1:1 with `files`; FK joins on `fileId`. Phase
/// 2 populates phash + dhash + width + height; videoFingerprint becomes useful in Phase 3.
public struct FingerprintRecord: Codable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "fingerprints"

    public var fileId: Int64
    public var phash: Data?            // 8-byte little-endian UInt64
    public var dhash: Data?            // 8-byte little-endian UInt64
    public var width: Int64?
    public var height: Int64?
    public var videoFingerprint: Data? // variable-length per-frame phash sequence (Phase 3)

    public init(
        fileId: Int64,
        phash: Data? = nil,
        dhash: Data? = nil,
        width: Int64? = nil,
        height: Int64? = nil,
        videoFingerprint: Data? = nil
    ) {
        self.fileId = fileId
        self.phash = phash
        self.dhash = dhash
        self.width = width
        self.height = height
        self.videoFingerprint = videoFingerprint
    }
}

/// Helpers for round-tripping a UInt64 hash through SQLite as 8 little-endian bytes. We
/// use a fixed encoding rather than `Data(bytes: &x, count: 8)` so the same database can
/// be opened on big-endian platforms without silently flipping every comparison.
extension UInt64 {
    public init(littleEndianHashData data: Data) {
        precondition(data.count == 8, "Hash blob must be 8 bytes")
        var v: UInt64 = 0
        for i in 0..<8 {
            v |= UInt64(data[data.startIndex + i]) << UInt64(i * 8)
        }
        self = v
    }

    public var littleEndianHashData: Data {
        var bytes = [UInt8](repeating: 0, count: 8)
        for i in 0..<8 {
            bytes[i] = UInt8((self >> UInt64(i * 8)) & 0xFF)
        }
        return Data(bytes)
    }
}

/// Operation log row. Every move-to-trash, move-to-folder, or restore writes one of these
/// before doing the actual filesystem work — that ordering is what makes "undo last
/// operation" reliable across crashes.
public struct OperationLogRecord: Codable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "operation_log"

    public var id: Int64?
    public var timestampUnix: Int64
    public var operation: String         // "trash" | "move" | "restore"
    public var sourcePath: String
    public var destinationPath: String?
    public var fileSizeBytes: Int64?
    public var contentHash: Data?

    public init(
        id: Int64? = nil,
        timestampUnix: Int64,
        operation: String,
        sourcePath: String,
        destinationPath: String? = nil,
        fileSizeBytes: Int64? = nil,
        contentHash: Data? = nil
    ) {
        self.id = id
        self.timestampUnix = timestampUnix
        self.operation = operation
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.fileSizeBytes = fileSizeBytes
        self.contentHash = contentHash
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
