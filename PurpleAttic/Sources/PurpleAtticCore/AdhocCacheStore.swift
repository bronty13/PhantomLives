import Foundation
import GRDB

/// One cached row of the ad-hoc B2 store's file listing. This is a *local mirror* of what
/// `rclone lsjson` last reported (decrypted names), so the browse UI, reports, and "what changed
/// since last refresh" are instant and offline — without re-hitting B2 every time. The remote is
/// always the source of truth; this is a cache that a Refresh rebuilds.
public struct AdhocFile: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    public var path: String          // decrypted object path within the store — the primary key
    public var name: String
    public var size: Int64
    public var modTime: Date
    public var isDir: Bool
    public var mimeType: String?
    public var sha1: String?
    public var remoteID: String?
    public var tier: String?
    /// When this row was last confirmed present in a listing — used to prune rows for objects that
    /// have disappeared from the remote since the previous refresh.
    public var lastSeen: Date

    public var id: String { path }
    public static let databaseTableName = "adhoc_file"

    public init(path: String, name: String, size: Int64, modTime: Date, isDir: Bool,
                mimeType: String? = nil, sha1: String? = nil, remoteID: String? = nil,
                tier: String? = nil, lastSeen: Date) {
        self.path = path
        self.name = name
        self.size = size
        self.modTime = modTime
        self.isDir = isDir
        self.mimeType = mimeType
        self.sha1 = sha1
        self.remoteID = remoteID
        self.tier = tier
        self.lastSeen = lastSeen
    }

    public init(remote f: AdhocRemoteFile, lastSeen: Date) {
        self.init(path: f.path, name: f.name, size: f.size, modTime: f.modTime, isDir: f.isDir,
                  mimeType: f.mimeType, sha1: f.sha1, remoteID: f.id, tier: f.tier, lastSeen: lastSeen)
    }
}

/// SQLite-backed cache of the ad-hoc B2 file listing (GRDB). Lives in the app's internal config dir
/// — caches/logs/config belong under Application Support, not the user-visible Downloads tree.
///
/// **Migrations are append-only and immutable** (the PhantomLives SQL-migration rule): once a
/// migration identifier ships, never change its body — add a new one. `migrationIdentifiers` is the
/// frozen, ordered list a guard test asserts against, the GRDB analog of SideMolly's
/// `EXPECTED_MIGRATION_HASHES`.
public final class AdhocCacheStore {

    /// Frozen, ordered list of registered migration identifiers. Append new ones; never edit/remove.
    public static let migrationIdentifiers = ["v1-create-adhoc-file"]

    private let dbQueue: DatabaseQueue

    /// Default on-disk cache path: ~/Library/Application Support/PurpleAttic/adhoc-cache.sqlite.
    public static func defaultURL() -> URL {
        ProfileStore.defaultDirectory().appendingPathComponent("adhoc-cache.sqlite")
    }

    /// Open (creating if needed) the cache at `url`, running migrations.
    public init(url: URL = AdhocCacheStore.defaultURL()) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        dbQueue = try DatabaseQueue(path: url.path)
        try Self.migrator.migrate(dbQueue)
    }

    /// In-memory store for tests (no file touched).
    public init(inMemory: Bool) throws {
        precondition(inMemory)
        dbQueue = try DatabaseQueue()
        try Self.migrator.migrate(dbQueue)
    }

    private static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration(migrationIdentifiers[0]) { db in
            try db.create(table: AdhocFile.databaseTableName) { t in
                t.column("path", .text).notNull().primaryKey()
                t.column("name", .text).notNull()
                t.column("size", .integer).notNull()
                t.column("modTime", .datetime).notNull()
                t.column("isDir", .boolean).notNull().defaults(to: false)
                t.column("mimeType", .text)
                t.column("sha1", .text)
                t.column("remoteID", .text)
                t.column("tier", .text)
                t.column("lastSeen", .datetime).notNull()
            }
        }
        return m
    }

    // MARK: - Mutations

    /// Replace the cache with a fresh listing: upsert every file (stamping `lastSeen = refreshedAt`),
    /// then prune any row not seen in this refresh (i.e. removed from the remote). Done in one
    /// transaction so a reader never sees a half-applied refresh.
    public func replaceFromListing(_ files: [AdhocRemoteFile], refreshedAt: Date) throws {
        try dbQueue.write { db in
            for f in files {
                try AdhocFile(remote: f, lastSeen: refreshedAt).save(db)
            }
            try AdhocFile.filter(Column("lastSeen") < refreshedAt).deleteAll(db)
        }
    }

    /// Remove a single cached row (e.g. right after a successful remote delete, so the UI updates
    /// without a full refresh).
    public func remove(path: String) throws {
        _ = try dbQueue.write { db in try AdhocFile.deleteOne(db, key: path) }
    }

    /// Upsert a single cached row (e.g. to reflect a rename's new path without a full refresh).
    public func put(_ file: AdhocFile) throws {
        try dbQueue.write { db in try file.save(db) }
    }

    /// Drop everything (e.g. when the store is reconfigured/disconnected).
    public func clear() throws {
        _ = try dbQueue.write { db in try AdhocFile.deleteAll(db) }
    }

    // MARK: - Queries

    /// All cached files, ordered by path by default (the natural tree order for the browse UI).
    public func allFiles(orderByName: Bool = false) throws -> [AdhocFile] {
        try dbQueue.read { db in
            let key = orderByName ? "name" : "path"
            return try AdhocFile.order(Column(key)).fetchAll(db)
        }
    }

    /// Case-insensitive substring search over name/path (for the UI filter box).
    public func search(_ query: String) throws -> [AdhocFile] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return try allFiles() }
        let like = "%\(q)%"
        return try dbQueue.read { db in
            try AdhocFile
                .filter(Column("path").like(like) || Column("name").like(like))
                .order(Column("path"))
                .fetchAll(db)
        }
    }

    public func count() throws -> Int {
        try dbQueue.read { db in try AdhocFile.fetchCount(db) }
    }

    /// Total bytes of cached files (directories excluded; their size is rclone's -1 sentinel).
    public func totalSize() throws -> Int64 {
        try dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(size), 0) FROM \(AdhocFile.databaseTableName) WHERE isDir = 0") ?? 0
        }
    }
}
