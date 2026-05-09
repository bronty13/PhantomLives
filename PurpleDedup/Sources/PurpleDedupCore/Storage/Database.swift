import Foundation
import GRDB

/// SQLite cache. Phase 1 ships a minimal schema — `files` (with content hash) and
/// `operation_log`. The richer tables in the requirements doc (`fingerprints`, `metadata`,
/// `sessions`, `clusters`, `cluster_members`) are added by later phases that actually
/// populate them. Migrations are append-only; we never edit a registered migration in
/// place — see GRDB's docs on safe schema evolution.
public final class Database: @unchecked Sendable {

    public let writer: any DatabaseWriter

    public static let defaultFilename = "purplededup.sqlite"

    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// Open (or create) the production database under `~/Library/Application Support/PurpleDedup/`.
    public static func openDefault() throws -> Database {
        let supportDir = PurpleDedup.supportDirectoryURL
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let dbURL = supportDir.appendingPathComponent(defaultFilename)
        let pool = try DatabasePool(path: dbURL.path)
        return try Database(writer: pool)
    }

    /// In-memory database for tests. Each call returns a fresh, isolated DB.
    public static func inMemory() throws -> Database {
        let queue = try DatabaseQueue()
        return try Database(writer: queue)
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()

        m.registerMigration("v1_files_and_log") { db in
            try db.create(table: "files") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("path", .text).notNull().unique()
                t.column("sizeBytes", .integer).notNull()
                t.column("mtimeUnix", .integer).notNull()
                t.column("fileType", .text).notNull()
                t.column("format", .text).notNull()
                t.column("contentHash", .blob)
                t.column("lastIndexedUnix", .integer).notNull()
            }
            try db.create(index: "idx_files_size", on: "files", columns: ["sizeBytes"])
            try db.create(index: "idx_files_content_hash", on: "files", columns: ["contentHash"])

            try db.create(table: "operation_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestampUnix", .integer).notNull()
                t.column("operation", .text).notNull()
                t.column("sourcePath", .text).notNull()
                t.column("destinationPath", .text)
                t.column("fileSizeBytes", .integer)
                t.column("contentHash", .blob)
            }
            try db.create(index: "idx_oplog_timestamp", on: "operation_log", columns: ["timestampUnix"])
        }

        m.registerMigration("v2_fingerprints") { db in
            try db.create(table: "fingerprints") { t in
                t.column("fileId", .integer)
                    .primaryKey()
                    .references("files", column: "id", onDelete: .cascade)
                t.column("phash", .blob)
                t.column("dhash", .blob)
                t.column("width", .integer)
                t.column("height", .integer)
                t.column("videoFingerprint", .blob)
            }
        }

        return m
    }

    /// Upsert by path. Used during scan to populate the cache; if the file's size or mtime
    /// changed, the existing row is overwritten and `contentHash` is cleared so the next
    /// scan re-hashes it.
    public func upsertScanned(
        path: String,
        sizeBytes: Int64,
        mtimeUnix: Int64,
        fileType: String,
        format: String,
        contentHash: Data?
    ) throws {
        try writer.write { db in
            let now = Int64(Date().timeIntervalSince1970)
            if var existing = try FileRecord.filter(Column("path") == path).fetchOne(db) {
                let changed = existing.sizeBytes != sizeBytes || existing.mtimeUnix != mtimeUnix
                existing.sizeBytes = sizeBytes
                existing.mtimeUnix = mtimeUnix
                existing.fileType = fileType
                existing.format = format
                existing.lastIndexedUnix = now
                if changed {
                    existing.contentHash = contentHash
                } else if existing.contentHash == nil {
                    existing.contentHash = contentHash
                }
                try existing.update(db)
            } else {
                var rec = FileRecord(
                    path: path,
                    sizeBytes: sizeBytes,
                    mtimeUnix: mtimeUnix,
                    fileType: fileType,
                    format: format,
                    contentHash: contentHash,
                    lastIndexedUnix: now
                )
                try rec.insert(db)
            }
        }
    }

    public func recordOperation(
        operation: String,
        sourcePath: String,
        destinationPath: String?,
        fileSizeBytes: Int64?,
        contentHash: Data?
    ) throws {
        try writer.write { db in
            var rec = OperationLogRecord(
                timestampUnix: Int64(Date().timeIntervalSince1970),
                operation: operation,
                sourcePath: sourcePath,
                destinationPath: destinationPath,
                fileSizeBytes: fileSizeBytes,
                contentHash: contentHash
            )
            try rec.insert(db)
        }
    }

    /// One-call batch upsert for `files`. Used by `CachedScanEngine` to drop hundreds of
    /// hash results into the DB in a single transaction — sequencing them through the
    /// per-file `upsertScanned` path was the dominant cost on large libraries on
    /// fast disks (each call is its own transaction → serial through GRDB's writer
    /// queue → fsync per row).
    public struct ScannedFile: Sendable {
        public let path: String
        public let sizeBytes: Int64
        public let mtimeUnix: Int64
        public let fileType: String
        public let format: String
        public let contentHash: Data?

        public init(path: String, sizeBytes: Int64, mtimeUnix: Int64, fileType: String, format: String, contentHash: Data?) {
            self.path = path; self.sizeBytes = sizeBytes; self.mtimeUnix = mtimeUnix
            self.fileType = fileType; self.format = format; self.contentHash = contentHash
        }
    }

    public func upsertScannedBatch(_ rows: [ScannedFile]) throws {
        guard !rows.isEmpty else { return }
        try writer.write { db in
            let now = Int64(Date().timeIntervalSince1970)
            for row in rows {
                if var existing = try FileRecord.filter(Column("path") == row.path).fetchOne(db) {
                    let changed = existing.sizeBytes != row.sizeBytes || existing.mtimeUnix != row.mtimeUnix
                    existing.sizeBytes = row.sizeBytes
                    existing.mtimeUnix = row.mtimeUnix
                    existing.fileType = row.fileType
                    existing.format = row.format
                    existing.lastIndexedUnix = now
                    if changed {
                        existing.contentHash = row.contentHash
                    } else if existing.contentHash == nil {
                        existing.contentHash = row.contentHash
                    }
                    try existing.update(db)
                } else {
                    var rec = FileRecord(
                        path: row.path,
                        sizeBytes: row.sizeBytes,
                        mtimeUnix: row.mtimeUnix,
                        fileType: row.fileType,
                        format: row.format,
                        contentHash: row.contentHash,
                        lastIndexedUnix: now
                    )
                    try rec.insert(db)
                }
            }
        }
    }

    public struct FingerprintWrite: Sendable {
        public let path: String
        public let sizeBytes: Int64
        public let mtimeUnix: Int64
        public let fileType: String
        public let format: String
        public let phash: UInt64?
        public let dhash: UInt64?
        public let width: Int?
        public let height: Int?
        public let videoFingerprint: Data?

        public init(path: String, sizeBytes: Int64, mtimeUnix: Int64, fileType: String, format: String, phash: UInt64?, dhash: UInt64?, width: Int?, height: Int?, videoFingerprint: Data?) {
            self.path = path; self.sizeBytes = sizeBytes; self.mtimeUnix = mtimeUnix
            self.fileType = fileType; self.format = format
            self.phash = phash; self.dhash = dhash
            self.width = width; self.height = height
            self.videoFingerprint = videoFingerprint
        }
    }

    public func upsertFingerprintsBatch(_ rows: [FingerprintWrite]) throws {
        guard !rows.isEmpty else { return }
        try writer.write { db in
            let now = Int64(Date().timeIntervalSince1970)
            for row in rows {
                let fileId: Int64
                if var existing = try FileRecord.filter(Column("path") == row.path).fetchOne(db) {
                    existing.sizeBytes = row.sizeBytes
                    existing.mtimeUnix = row.mtimeUnix
                    existing.fileType = row.fileType
                    existing.format = row.format
                    existing.lastIndexedUnix = now
                    try existing.update(db)
                    fileId = existing.id ?? 0
                } else {
                    var rec = FileRecord(
                        path: row.path,
                        sizeBytes: row.sizeBytes,
                        mtimeUnix: row.mtimeUnix,
                        fileType: row.fileType,
                        format: row.format,
                        contentHash: nil,
                        lastIndexedUnix: now
                    )
                    try rec.insert(db)
                    fileId = rec.id ?? 0
                }
                guard fileId != 0 else { continue }
                try FingerprintRecord.filter(Column("fileId") == fileId).deleteAll(db)
                if row.phash != nil || row.dhash != nil || row.videoFingerprint != nil {
                    var fp = FingerprintRecord(
                        fileId: fileId,
                        phash: row.phash?.littleEndianHashData,
                        dhash: row.dhash?.littleEndianHashData,
                        width: row.width.map { Int64($0) },
                        height: row.height.map { Int64($0) },
                        videoFingerprint: row.videoFingerprint
                    )
                    try fp.insert(db)
                }
            }
        }
    }

    /// Bulk load every (file, fingerprint) pair in one read. Returns a path-keyed
    /// dictionary so callers can do an in-memory `O(1)` cache lookup per scanned file
    /// instead of a per-file `SELECT … WHERE path = ?`. On a 4000-file scan that's
    /// the difference between 4000 SQLite round trips (~2s on NVMe) and one (~50ms).
    public struct CachedRow: Sendable {
        public let file: FileRecord
        public let fingerprint: FingerprintRecord?
    }

    public func loadAllCachedRows() throws -> [String: CachedRow] {
        try writer.read { db in
            let files = try FileRecord.fetchAll(db)
            let fps = try FingerprintRecord.fetchAll(db)
            var fpsByFileId: [Int64: FingerprintRecord] = [:]
            for fp in fps { fpsByFileId[fp.fileId] = fp }
            var result: [String: CachedRow] = [:]
            result.reserveCapacity(files.count)
            for f in files {
                result[f.path] = CachedRow(
                    file: f,
                    fingerprint: f.id.flatMap { fpsByFileId[$0] }
                )
            }
            return result
        }
    }

    public func fileCount() throws -> Int {
        try writer.read { db in
            try FileRecord.fetchCount(db)
        }
    }

    /// Read the row for a given path, if any. Returns nil for cache misses (file never
    /// scanned before). Caller is responsible for the size/mtime "still fresh" check —
    /// this method just hands back what's persisted.
    public func file(at path: String) throws -> FileRecord? {
        try writer.read { db in
            try FileRecord.filter(Column("path") == path).fetchOne(db)
        }
    }

    /// Read the perceptual fingerprint row (if any) for a file by path. One DB hop
    /// returning the fingerprint *and* the file row, since the cache check usually
    /// needs both — separate fetches would do twice the work.
    public func fileWithFingerprint(at path: String) throws -> (FileRecord, FingerprintRecord?)? {
        try writer.read { db in
            guard let file = try FileRecord.filter(Column("path") == path).fetchOne(db),
                  let fileId = file.id else { return nil }
            let fp = try FingerprintRecord.filter(Column("fileId") == fileId).fetchOne(db)
            return (file, fp)
        }
    }

    /// Upsert (file, fingerprint) atomically. The fingerprint row uses ON CONFLICT
    /// REPLACE semantics — a re-hashed file overwrites its old hashes in place.
    public func upsertFingerprint(
        forPath path: String,
        sizeBytes: Int64,
        mtimeUnix: Int64,
        fileType: String,
        format: String,
        contentHash: Data?,
        phash: UInt64?,
        dhash: UInt64?,
        width: Int?,
        height: Int?,
        videoFingerprint: Data?
    ) throws {
        try writer.write { db in
            let now = Int64(Date().timeIntervalSince1970)
            // Upsert files row.
            let fileId: Int64
            if var existing = try FileRecord.filter(Column("path") == path).fetchOne(db) {
                existing.sizeBytes = sizeBytes
                existing.mtimeUnix = mtimeUnix
                existing.fileType = fileType
                existing.format = format
                existing.contentHash = contentHash ?? existing.contentHash
                existing.lastIndexedUnix = now
                try existing.update(db)
                fileId = existing.id ?? 0
            } else {
                var rec = FileRecord(
                    path: path,
                    sizeBytes: sizeBytes,
                    mtimeUnix: mtimeUnix,
                    fileType: fileType,
                    format: format,
                    contentHash: contentHash,
                    lastIndexedUnix: now
                )
                try rec.insert(db)
                fileId = rec.id ?? 0
            }
            guard fileId != 0 else { return }

            // Upsert fingerprint. SQLite REPLACE via delete-then-insert on the PK. We
            // could use INSERT…ON CONFLICT but GRDB's MutablePersistableRecord makes
            // the explicit pattern clearer.
            try FingerprintRecord.filter(Column("fileId") == fileId).deleteAll(db)
            if phash != nil || dhash != nil || videoFingerprint != nil {
                var fp = FingerprintRecord(
                    fileId: fileId,
                    phash: phash?.littleEndianHashData,
                    dhash: dhash?.littleEndianHashData,
                    width: width.map { Int64($0) },
                    height: height.map { Int64($0) },
                    videoFingerprint: videoFingerprint
                )
                try fp.insert(db)
            }
        }
    }
}
