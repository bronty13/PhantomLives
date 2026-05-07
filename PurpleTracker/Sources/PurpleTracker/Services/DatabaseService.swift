import Foundation
import GRDB

/// Sole owner of the GRDB pool for `purpletracker.sqlite`. Owns migrations,
/// seeds defaults, and exposes thin per-record CRUD wrappers used by AppState.
@MainActor
final class DatabaseService {
    static let shared = DatabaseService()

    private(set) var dbPool: DatabasePool

    static var supportDirectory: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("PurpleTracker", isDirectory: true)
    }

    var databaseURL: URL { Self.supportDirectory.appendingPathComponent("purpletracker.sqlite") }

    private init() {
        let dir = Self.supportDirectory
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbPool = try! DatabasePool(path: dir.appendingPathComponent("purpletracker.sqlite").path)
        try! Self.applyMigrations(to: dbPool)
        try? seedDefaults()
    }

    /// Re-open the pool against the on-disk file — used after a backup restore.
    func reopenDatabase() throws {
        dbPool = try DatabasePool(path: databaseURL.path)
        try Self.applyMigrations(to: dbPool)
    }

    // MARK: - Migrations

    /// Public so tests can apply the *real* schema to an in-memory queue
    /// without duplicating the migration body.
    static func applyMigrations(to writer: DatabaseWriter) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "matter_type") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("color_hex", .text).notNull().defaults(to: "#888888")
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("is_cadenced", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "status_value") { t in
                t.column("name", .text).primaryKey()
                t.column("sort_order", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "cadence") { t in
                t.column("id", .text).primaryKey()
                t.column("kind", .text).notNull()
                t.column("custom_interval_days", .integer)
            }

            try db.create(table: "matter_id_counter") { t in
                t.column("date", .text).primaryKey()    // YYYY-MM-DD
                t.column("next_seq", .integer).notNull().defaults(to: 1)
            }

            try db.create(table: "matter") { t in
                t.column("id", .text).primaryKey()      // YYYY-MM-DD-#####
                t.column("title", .text).notNull().defaults(to: "")
                t.column("type_id", .text).notNull()
                    .references("matter_type", column: "id", onDelete: .restrict)
                t.column("status", .text).notNull().defaults(to: "New")
                t.column("description_md", .text).notNull().defaults(to: "")
                t.column("due_at", .datetime)
                t.column("created_at", .datetime).notNull()
                t.column("accessed_at", .datetime).notNull()
                t.column("modified_at", .datetime).notNull()
                t.column("external1_number", .text).notNull().defaults(to: "")
                t.column("external1_url", .text).notNull().defaults(to: "")
                t.column("external2_number", .text).notNull().defaults(to: "")
                t.column("external2_url", .text).notNull().defaults(to: "")
                t.column("external3_number", .text).notNull().defaults(to: "")
                t.column("external3_url", .text).notNull().defaults(to: "")
                t.column("time_tracking_code", .text).notNull().defaults(to: "")
                t.column("resolution_md", .text).notNull().defaults(to: "")
                t.column("lessons_md", .text).notNull().defaults(to: "")
                t.column("notes_md", .text).notNull().defaults(to: "")
                t.column("file_store_primary", .text).notNull().defaults(to: "")
                t.column("file_store_secondary", .text).notNull().defaults(to: "")
                t.column("cadence_id", .text)
                    .references("cadence", column: "id", onDelete: .setNull)
                t.column("parent_matter_id", .text)
                    .references("matter", column: "id", onDelete: .setNull)
            }
            try db.create(index: "idx_matter_status",   on: "matter", columns: ["status"])
            try db.create(index: "idx_matter_type",     on: "matter", columns: ["type_id"])
            try db.create(index: "idx_matter_due",      on: "matter", columns: ["due_at"])

            try db.create(table: "time_entry") { t in
                t.column("id", .text).primaryKey()
                t.column("matter_id", .text).notNull()
                    .references("matter", column: "id", onDelete: .cascade)
                t.column("started_at", .datetime).notNull()
                t.column("ended_at", .datetime)
                t.column("seconds", .integer).notNull().defaults(to: 0)
                t.column("note", .text).notNull().defaults(to: "")
            }
            try db.create(index: "idx_time_entry_matter", on: "time_entry", columns: ["matter_id"])
            try db.create(index: "idx_time_entry_start",  on: "time_entry", columns: ["started_at"])

            try db.create(table: "note") { t in
                t.column("id", .text).primaryKey()
                t.column("matter_id", .text).notNull()
                    .references("matter", column: "id", onDelete: .cascade)
                t.column("body_md", .text).notNull().defaults(to: "")
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(index: "idx_note_matter", on: "note", columns: ["matter_id"])

            try db.create(table: "attachment") { t in
                t.column("id", .text).primaryKey()
                t.column("matter_id", .text).notNull()
                    .references("matter", column: "id", onDelete: .cascade)
                t.column("filename", .text).notNull()
                t.column("size_bytes", .integer).notNull().defaults(to: 0)
                t.column("mime_type", .text).notNull().defaults(to: "application/octet-stream")
                t.column("data", .blob).notNull()
                t.column("md5", .text).notNull()
                t.column("sha1", .text).notNull()
                t.column("sha256", .text).notNull()
                t.column("added_at", .datetime).notNull()
                t.column("last_verified_at", .datetime)
                t.column("last_verify_ok", .integer).notNull().defaults(to: 1)
            }
            try db.create(index: "idx_attachment_matter", on: "attachment", columns: ["matter_id"])
        }

        try migrator.migrate(writer)
    }

    /// Seed defaults only when each table is empty so user edits survive
    /// every relaunch.
    private func seedDefaults() throws {
        try dbPool.write { db in
            let typeCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM matter_type") ?? 0
            if typeCount == 0 {
                for (i, t) in MatterType.seedTypes.enumerated() {
                    var row = MatterType(
                        id: UUID().uuidString,
                        name: t.name,
                        colorHex: t.color,
                        sortOrder: i,
                        isCadenced: t.cadenced
                    )
                    try row.insert(db)
                }
            }
            let statusCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM status_value") ?? 0
            if statusCount == 0 {
                for (i, s) in MatterStatus.defaultLifecycle.enumerated() {
                    try db.execute(
                        sql: "INSERT INTO status_value (name, sort_order) VALUES (?, ?)",
                        arguments: [s.rawValue, i]
                    )
                }
            }
        }
    }

    // MARK: - Matter

    func fetchAllMatters() throws -> [Matter] {
        try dbPool.read { db in
            try Matter.order(Column("modified_at").desc).fetchAll(db)
        }
    }

    func fetchMatter(id: String) throws -> Matter? {
        try dbPool.read { db in try Matter.fetchOne(db, key: id) }
    }

    func insertMatter(_ matter: Matter) throws {
        try dbPool.write { db in
            var m = matter
            try m.insert(db)
        }
    }

    /// Update + bump `modified_at` to now.
    func updateMatter(_ matter: Matter) throws {
        var m = matter
        m.modifiedAt = Date()
        try dbPool.write { db in try m.update(db) }
    }

    /// Touch `accessed_at` only (does not bump `modified_at`).
    func touchAccessed(matterId: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "UPDATE matter SET accessed_at = ? WHERE id = ?",
                arguments: [Date(), matterId]
            )
        }
    }

    func deleteMatter(id: String) throws {
        try dbPool.write { db in _ = try Matter.deleteOne(db, key: id) }
    }

    // MARK: - Matter type

    func fetchAllTypes() throws -> [MatterType] {
        try dbPool.read { db in
            try MatterType.order(Column("sort_order").asc).fetchAll(db)
        }
    }

    func saveType(_ t: MatterType) throws {
        try dbPool.write { db in
            var m = t
            try m.save(db)
        }
    }

    func deleteType(id: String) throws {
        try dbPool.write { db in _ = try MatterType.deleteOne(db, key: id) }
    }

    // MARK: - Status pick-list

    func fetchStatusValues() throws -> [(name: String, sortOrder: Int)] {
        try dbPool.read { db in
            try Row.fetchAll(db, sql: "SELECT name, sort_order FROM status_value ORDER BY sort_order ASC")
                .map { ($0["name"], $0["sort_order"]) }
        }
    }

    func replaceStatusValues(_ values: [(name: String, sortOrder: Int)]) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM status_value")
            for v in values {
                try db.execute(
                    sql: "INSERT INTO status_value (name, sort_order) VALUES (?, ?)",
                    arguments: [v.name, v.sortOrder]
                )
            }
        }
    }

    // MARK: - Cadence

    func saveCadence(_ c: Cadence) throws {
        try dbPool.write { db in
            try db.execute(
                sql: """
                INSERT INTO cadence (id, kind, custom_interval_days)
                VALUES (?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    kind = excluded.kind,
                    custom_interval_days = excluded.custom_interval_days
                """,
                arguments: [c.id, c.kind.rawValue, c.customIntervalDays]
            )
        }
    }

    func fetchCadence(id: String) throws -> Cadence? {
        try dbPool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT id, kind, custom_interval_days FROM cadence WHERE id = ?",
                arguments: [id]
            ) else { return nil }
            let kindStr: String = row["kind"]
            return Cadence(
                id: row["id"],
                kind: CadenceKind(rawValue: kindStr) ?? .weekly,
                customIntervalDays: row["custom_interval_days"]
            )
        }
    }

    // MARK: - Time entries

    func fetchTimeEntries(matterId: String) throws -> [TimeEntry] {
        try dbPool.read { db in
            try TimeEntry
                .filter(Column("matter_id") == matterId)
                .order(Column("started_at").desc)
                .fetchAll(db)
        }
    }

    func fetchAllTimeEntries() throws -> [TimeEntry] {
        try dbPool.read { db in
            try TimeEntry.order(Column("started_at").desc).fetchAll(db)
        }
    }

    func insertTimeEntry(_ entry: TimeEntry) throws {
        try dbPool.write { db in
            var m = entry
            try m.insert(db)
        }
    }

    func updateTimeEntry(_ entry: TimeEntry) throws {
        try dbPool.write { db in try entry.update(db) }
    }

    func deleteTimeEntry(id: String) throws {
        try dbPool.write { db in _ = try TimeEntry.deleteOne(db, key: id) }
    }

    /// Total seconds logged on this matter (ignores in-flight entries with no end).
    func totalSeconds(matterId: String) throws -> Int {
        try dbPool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(seconds), 0) FROM time_entry WHERE matter_id = ?",
                arguments: [matterId]
            ) ?? 0
        }
    }

    // MARK: - Notes

    func fetchNotes(matterId: String) throws -> [Note] {
        try dbPool.read { db in
            try Note
                .filter(Column("matter_id") == matterId)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    func saveNote(_ n: Note) throws {
        try dbPool.write { db in
            var m = n
            try m.save(db)
        }
    }

    func deleteNote(id: String) throws {
        try dbPool.write { db in _ = try Note.deleteOne(db, key: id) }
    }

    // MARK: - Attachments

    func fetchAttachments(matterId: String) throws -> [Attachment] {
        try dbPool.read { db in
            try Attachment
                .filter(Column("matter_id") == matterId)
                .order(Column("added_at").asc)
                .fetchAll(db)
        }
    }

    /// Metadata-only fetch (excludes the `data` BLOB) for list views that
    /// don't need to page potentially large payloads in.
    func fetchAttachmentMetadata(matterId: String) throws -> [(id: String, filename: String, sizeBytes: Int64, mimeType: String, sha1: String, lastVerifyOk: Bool)] {
        try dbPool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, filename, size_bytes, mime_type, sha1, last_verify_ok
                FROM attachment
                WHERE matter_id = ?
                ORDER BY added_at ASC
                """, arguments: [matterId])
            .map { row in
                (
                    id: row["id"] as String,
                    filename: row["filename"] as String,
                    sizeBytes: row["size_bytes"] as Int64,
                    mimeType: row["mime_type"] as String,
                    sha1: row["sha1"] as String,
                    lastVerifyOk: (row["last_verify_ok"] as Int) != 0
                )
            }
        }
    }

    func insertAttachment(_ a: Attachment) throws {
        try dbPool.write { db in
            var m = a
            try m.insert(db)
        }
    }

    func updateAttachmentVerification(id: String, at date: Date, ok: Bool) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "UPDATE attachment SET last_verified_at = ?, last_verify_ok = ? WHERE id = ?",
                arguments: [date, ok ? 1 : 0, id]
            )
        }
    }

    func deleteAttachment(id: String) throws {
        try dbPool.write { db in _ = try Attachment.deleteOne(db, key: id) }
    }
}
