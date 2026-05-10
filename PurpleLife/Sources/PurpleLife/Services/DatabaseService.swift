import Foundation
import GRDB

/// Sole owner of the GRDB `DatabasePool` for `purplelife.sqlite`. Runs the
/// append-only migrator at init and exposes thin per-record CRUD wrappers.
/// Migration logic lives in `static applyMigrations(to:)` so the test suite
/// applies the *real* migrator instead of a duplicated fixture — drift
/// between production schema and tests would defeat the migration tests.
@MainActor
final class DatabaseService {
    static let shared = DatabaseService()

    private(set) var dbPool: DatabasePool

    static var supportDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("PurpleLife", isDirectory: true)
    }

    var databaseURL: URL {
        Self.supportDirectory.appendingPathComponent("purplelife.sqlite")
    }

    var attachmentsDirectory: URL {
        Self.supportDirectory.appendingPathComponent("attachments", isDirectory: true)
    }

    private init() {
        let dir = Self.supportDirectory
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let attDir = dir.appendingPathComponent("attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: attDir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("purplelife.sqlite")
        dbPool = try! DatabasePool(path: dbURL.path)
        try! migrate()
    }

    /// Re-open the underlying GRDB pool against the on-disk database. Used
    /// after a backup-restore so the running process picks up the swapped file.
    func reopenDatabase() throws {
        dbPool = try DatabasePool(path: databaseURL.path)
        try migrate()
    }

    // MARK: - Migrations

    private func migrate() throws {
        try Self.applyMigrations(to: dbPool)
    }

    /// Public entry point so tests can apply the real schema to an in-memory
    /// `DatabaseQueue`. Add new versions to this function — never inside
    /// `init()` — to keep test coverage automatic.
    /// Marked `nonisolated` so test helpers don't all need `@MainActor`;
    /// the body is pure schema construction with no actor-isolated state.
    nonisolated static func applyMigrations(to writer: DatabaseWriter) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_objects") { db in
            // Single objects table per the storage shape locked in PLAN.md.
            // Typed columns for things every object has + a JSON `fields_json`
            // blob for everything else. The blob travels through CloudKit's
            // `encryptedValues` in Phase 4; locally it's plaintext (FileVault
            // is the on-disk encryption layer).
            try db.create(table: "objects") { t in
                t.column("id", .text).primaryKey()
                t.column("type_id", .text).notNull()
                t.column("parent_id", .text)
                t.column("fields_json", .text).notNull().defaults(to: "{}")
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.create(index: "idx_objects_type",       on: "objects", columns: ["type_id"])
            try db.create(index: "idx_objects_parent",     on: "objects", columns: ["parent_id"])
            try db.create(index: "idx_objects_updated_at", on: "objects", columns: ["updated_at"])
        }

        // v2 — attachments metadata table. Per the attachments decision in
        // HANDOFF.md (2026-05-10), file content lives at
        // ~/Library/Application Support/PurpleLife/attachments/<sha256>.<ext>;
        // this table is metadata only. Content-addressing means the same
        // file referenced by multiple objects de-duplicates on disk.
        migrator.registerMigration("v2_attachments") { db in
            try db.create(table: "attachments") { t in
                t.column("id", .text).primaryKey()
                t.column("parent_object_id", .text).notNull()
                    .references("objects", column: "id", onDelete: .cascade)
                t.column("field_key", .text).notNull()
                t.column("sha256", .text).notNull()
                t.column("filename", .text).notNull()
                t.column("mime_type", .text).notNull().defaults(to: "application/octet-stream")
                t.column("size_bytes", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).notNull()
            }
            try db.create(index: "idx_attachments_parent",
                          on: "attachments",
                          columns: ["parent_object_id"])
            try db.create(index: "idx_attachments_sha256",
                          on: "attachments",
                          columns: ["sha256"])
        }

        // v3 — FTS5 virtual table for `SearchService`. Phase 2 search runs
        // over decrypted fields at index time; the FTS table is rebuilt
        // from scratch on launch (cheap for the row counts we'll see) and
        // maintained incrementally on each ObjectEngine mutation. The
        // recommended `objects_fts` shape: typed `object_id` + `type_id`
        // (UNINDEXED so `MATCH` doesn't consider them), plus `title` and
        // `body` text content.
        migrator.registerMigration("v3_fts5") { db in
            try db.create(virtualTable: "objects_fts", using: FTS5()) { t in
                t.tokenizer = .porter()
                t.column("object_id").notIndexed()
                t.column("type_id").notIndexed()
                t.column("title")
                t.column("body")
            }
        }

        try migrator.migrate(writer)
    }

    // MARK: - Object CRUD

    func insertObject(_ object: ObjectRecord) throws {
        try dbPool.write { db in
            try object.insert(db)
        }
    }

    func updateObject(_ object: ObjectRecord) throws {
        var stamped = object
        stamped.updatedAt = Self.isoNow()
        try dbPool.write { db in
            try stamped.update(db)
        }
    }

    func upsertObject(_ object: ObjectRecord) throws {
        try dbPool.write { db in
            try object.save(db)
        }
    }

    func deleteObject(id: String) throws {
        try dbPool.write { db in
            _ = try ObjectRecord.deleteOne(db, key: id)
        }
    }

    func fetchObject(id: String) throws -> ObjectRecord? {
        try dbPool.read { db in
            try ObjectRecord.fetchOne(db, key: id)
        }
    }

    func fetchAllObjects() throws -> [ObjectRecord] {
        try dbPool.read { db in
            try ObjectRecord.order(Column("updated_at").desc).fetchAll(db)
        }
    }

    func fetchObjects(typeId: String) throws -> [ObjectRecord] {
        try dbPool.read { db in
            try ObjectRecord
                .filter(Column("type_id") == typeId)
                .order(Column("updated_at").desc)
                .fetchAll(db)
        }
    }

    func fetchChildren(parentId: String) throws -> [ObjectRecord] {
        try dbPool.read { db in
            try ObjectRecord
                .filter(Column("parent_id") == parentId)
                .order(Column("updated_at").desc)
                .fetchAll(db)
        }
    }

    func objectCount() throws -> Int {
        try dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM objects") ?? 0
        }
    }

    func objectCount(typeId: String) throws -> Int {
        try dbPool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM objects WHERE type_id = ?",
                arguments: [typeId]
            ) ?? 0
        }
    }

    // MARK: - Helpers

    static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
