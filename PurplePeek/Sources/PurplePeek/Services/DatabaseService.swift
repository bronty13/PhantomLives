import Foundation
import GRDB

/// Sole owner of the GRDB `DatabasePool` for `purplepeek.sqlite`. Runs the append-only
/// migrator at init and exposes thin per-record CRUD wrappers. Migration logic lives in
/// `static applyMigrations(to:)` so the test suite applies the *real* migrator against an
/// in-memory database instead of a duplicated fixture that would drift over time.
@MainActor
final class DatabaseService {
    static let shared = DatabaseService()

    private(set) var dbPool: DatabasePool

    static var supportDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("PurplePeek", isDirectory: true)
    }

    var databaseURL: URL {
        Self.supportDirectory.appendingPathComponent("purplepeek.sqlite")
    }

    private init() {
        let dir = Self.supportDirectory
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("purplepeek.sqlite")
        dbPool = try! DatabasePool(path: dbURL.path)
        try! migrate()
    }

    /// Re-open the underlying GRDB pool against the on-disk database. Used after a
    /// backup-restore so the running process picks up the swapped file.
    func reopenDatabase() throws {
        dbPool = try DatabasePool(path: databaseURL.path)
        try migrate()
    }

    // MARK: - Migrations

    private func migrate() throws {
        try Self.applyMigrations(to: dbPool)
    }

    /// Public entry point so tests can apply the real schema to an in-memory
    /// `DatabaseQueue`. Add new versions here — never inside `init()` — and never edit a
    /// shipped migration (migrations are immutable once committed; see CLAUDE.md).
    static func applyMigrations(to writer: DatabaseWriter) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "scan_roots") { t in
                t.column("path", .text).primaryKey()
                t.column("last_scanned_at", .text).notNull()
                t.column("total_files", .integer).notNull().defaults(to: 0)
                t.column("label", .text)
            }

            try db.create(table: "media_files") { t in
                t.column("id", .text).primaryKey()
                t.column("scan_root", .text).notNull()
                    .references("scan_roots", column: "path", onDelete: .cascade)
                t.column("file_path", .text).notNull().unique()
                t.column("file_name", .text).notNull()
                t.column("file_type", .text).notNull()      // photo | video | audio
                t.column("file_size", .integer)
                t.column("file_modified_at", .text)
                t.column("keep", .integer)                  // NULL=undecided, 1=keep, 0=skip
                t.column("is_favorite", .integer).notNull().defaults(to: 0)
                t.column("title", .text)
                t.column("caption", .text)
                t.column("imported_at", .text)
                t.column("exported_at", .text)
                t.column("deleted_at", .text)
                t.column("photos_asset_id", .text)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.create(index: "idx_media_files_scan_root",   on: "media_files", columns: ["scan_root"])
            try db.create(index: "idx_media_files_keep",         on: "media_files", columns: ["keep"])
            try db.create(index: "idx_media_files_imported_at",  on: "media_files", columns: ["imported_at"])
            try db.create(index: "idx_media_files_deleted_at",   on: "media_files", columns: ["deleted_at"])

            try db.create(table: "keywords") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull().unique().collate(.nocase)
                t.column("source", .text).notNull().defaults(to: "local")
                t.column("created_at", .text).notNull()
            }

            try db.create(table: "file_keywords") { t in
                t.column("file_id", .text).notNull()
                    .references("media_files", column: "id", onDelete: .cascade)
                t.column("keyword_id", .text).notNull()
                    .references("keywords", column: "id", onDelete: .cascade)
                t.primaryKey(["file_id", "keyword_id"])
            }
            try db.create(index: "idx_file_keywords_keyword", on: "file_keywords", columns: ["keyword_id"])

            try db.create(table: "file_albums") { t in
                t.column("file_id", .text).notNull()
                    .references("media_files", column: "id", onDelete: .cascade)
                t.column("album_name", .text).notNull()
                t.primaryKey(["file_id", "album_name"])
            }
            try db.create(index: "idx_file_albums_album", on: "file_albums", columns: ["album_name"])
        }

        try migrator.migrate(writer)
    }

    // MARK: - ScanRoot reads

    func fetchAllScanRoots() throws -> [ScanRoot] {
        try dbPool.read { db in
            try ScanRoot.order(Column("last_scanned_at").desc).fetchAll(db)
        }
    }

    // MARK: - MediaFile reads

    func fetchMediaFiles(scanRoot: String) throws -> [MediaFile] {
        try dbPool.read { db in
            try MediaFile
                .filter(Column("scan_root") == scanRoot)
                .order(Column("file_path"))
                .fetchAll(db)
        }
    }

    // MARK: - Keyword reads

    func fetchAllKeywords() throws -> [Keyword] {
        try dbPool.read { db in
            try Keyword.order(Column("name")).fetchAll(db)
        }
    }
}
