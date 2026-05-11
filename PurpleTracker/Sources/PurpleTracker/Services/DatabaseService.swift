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

        migrator.registerMigration("v2_people_and_requestor") { db in
            try db.create(table: "person") { t in
                t.column("id", .text).primaryKey()        // Associate ID
                t.column("first_name", .text).notNull().defaults(to: "")
                t.column("last_name", .text).notNull().defaults(to: "")
                t.column("preferred_name", .text).notNull().defaults(to: "")
                t.column("job_title", .text).notNull().defaults(to: "")
                t.column("work_email", .text).notNull().defaults(to: "")
                t.column("department", .text).notNull().defaults(to: "")
                t.column("location", .text).notNull().defaults(to: "")
                t.column("position_status", .text).notNull().defaults(to: "")
                t.column("manager_associate_id", .text).notNull().defaults(to: "")
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(index: "idx_person_last_first",
                          on: "person", columns: ["last_name", "first_name"])
            try db.create(index: "idx_person_status",
                          on: "person", columns: ["position_status"])

            try db.alter(table: "matter") { t in
                t.add(column: "requestor_associate_id", .text).defaults(to: "")
            }
        }

        migrator.registerMigration("v3_interested_parties") { db in
            try db.alter(table: "matter") { t in
                for i in 1...5 {
                    t.add(column: "interested_party\(i)_associate_id", .text).defaults(to: "")
                    t.add(column: "external_interested_party\(i)", .text).defaults(to: "")
                }
            }
        }

        migrator.registerMigration("v4_initiatives_goals_priority") { db in
            try db.alter(table: "matter") { t in
                t.add(column: "priority", .text).notNull().defaults(to: MatterPriority.defaultPriority.rawValue)
            }
            try db.create(index: "idx_matter_priority", on: "matter", columns: ["priority"])

            try db.create(table: "initiative") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("sort_order", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "goal") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("sort_order", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "matter_initiative") { t in
                t.column("matter_id", .text).notNull()
                    .references("matter", column: "id", onDelete: .cascade)
                t.column("initiative_id", .text).notNull()
                    .references("initiative", column: "id", onDelete: .cascade)
                t.primaryKey(["matter_id", "initiative_id"])
            }
            try db.create(index: "idx_matter_initiative_initiative",
                          on: "matter_initiative", columns: ["initiative_id"])
            try db.create(table: "matter_goal") { t in
                t.column("matter_id", .text).notNull()
                    .references("matter", column: "id", onDelete: .cascade)
                t.column("goal_id", .text).notNull()
                    .references("goal", column: "id", onDelete: .cascade)
                t.primaryKey(["matter_id", "goal_id"])
            }
            try db.create(index: "idx_matter_goal_goal",
                          on: "matter_goal", columns: ["goal_id"])
        }

        migrator.registerMigration("v5_subtasks_links_audit_trash_savedsearches") { db in
            // Soft-delete: set `deleted_at` to put a Matter in the Trash;
            // null = live. The 30-day purge sweep (AppState.purgeExpiredTrash)
            // hard-deletes anything older than that on launch.
            try db.alter(table: "matter") { t in
                t.add(column: "deleted_at", .datetime)
            }
            try db.create(index: "idx_matter_deleted_at", on: "matter", columns: ["deleted_at"])

            try db.create(table: "subtask") { t in
                t.column("id", .text).primaryKey()
                t.column("matter_id", .text).notNull()
                    .references("matter", column: "id", onDelete: .cascade)
                t.column("body", .text).notNull().defaults(to: "")
                t.column("done", .integer).notNull().defaults(to: 0)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("created_at", .datetime).notNull()
            }
            try db.create(index: "idx_subtask_matter", on: "subtask", columns: ["matter_id"])

            try db.create(table: "matter_link") { t in
                t.column("matter_id", .text).notNull()
                    .references("matter", column: "id", onDelete: .cascade)
                t.column("related_matter_id", .text).notNull()
                    .references("matter", column: "id", onDelete: .cascade)
                t.column("kind", .text).notNull().defaults(to: "related")  // 'related' | 'depends_on'
                t.primaryKey(["matter_id", "related_matter_id", "kind"])
            }

            try db.create(table: "audit_event") { t in
                t.column("id", .text).primaryKey()
                t.column("matter_id", .text).notNull()
                    .references("matter", column: "id", onDelete: .cascade)
                t.column("ts", .datetime).notNull()
                t.column("kind", .text).notNull()       // 'status', 'priority', 'type', 'title', 'tag', 'created', 'restored', 'deleted'
                t.column("before_value", .text).notNull().defaults(to: "")
                t.column("after_value", .text).notNull().defaults(to: "")
            }
            try db.create(index: "idx_audit_matter_ts",
                          on: "audit_event", columns: ["matter_id", "ts"])

            try db.create(table: "saved_search") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("query_json", .text).notNull().defaults(to: "{}")
                t.column("sort_order", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("v6_third_parties") { db in
            // Top-level Third Party (vendor) row.
            try db.create(table: "vendor") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull().defaults(to: "")
                t.column("address", .text).notNull().defaults(to: "")
                t.column("website", .text).notNull().defaults(to: "")
                t.column("phone", .text).notNull().defaults(to: "")
                t.column("reseller", .text).notNull().defaults(to: "")
                t.column("reseller_other", .text).notNull().defaults(to: "")
                t.column("rating", .integer)
                t.column("rating_note", .text).notNull().defaults(to: "")
                t.column("description_md", .text).notNull().defaults(to: "")
                t.column("data_center", .text).notNull().defaults(to: "")
                t.column("exit_strategy_md", .text).notNull().defaults(to: "")
                t.column("contract_summary_md", .text).notNull().defaults(to: "")
                t.column("costing_summary_md", .text).notNull().defaults(to: "")
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("deleted_at", .datetime)
            }
            try db.create(index: "idx_vendor_name", on: "vendor", columns: ["name"])
            try db.create(index: "idx_vendor_deleted_at", on: "vendor", columns: ["deleted_at"])

            try db.create(table: "vendor_contact") { t in
                t.column("id", .text).primaryKey()
                t.column("vendor_id", .text).notNull()
                    .references("vendor", column: "id", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("name", .text).notNull().defaults(to: "")
                t.column("phone", .text).notNull().defaults(to: "")
                t.column("mobile", .text).notNull().defaults(to: "")
                t.column("email", .text).notNull().defaults(to: "")
            }
            try db.create(index: "idx_vendor_contact_vendor",
                          on: "vendor_contact", columns: ["vendor_id"])

            try db.create(table: "vendor_product") { t in
                t.column("id", .text).primaryKey()
                t.column("vendor_id", .text).notNull()
                    .references("vendor", column: "id", onDelete: .cascade)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("name", .text).notNull().defaults(to: "")
                t.column("notes", .text).notNull().defaults(to: "")
            }
            try db.create(index: "idx_vendor_product_vendor",
                          on: "vendor_product", columns: ["vendor_id"])

            try db.create(table: "vendor_year_amount") { t in
                t.column("vendor_id", .text).notNull()
                    .references("vendor", column: "id", onDelete: .cascade)
                t.column("year", .integer).notNull()
                t.column("budget_cents", .integer).notNull().defaults(to: 0)
                t.column("actual_override_cents", .integer)
                t.primaryKey(["vendor_id", "year"])
            }

            try db.create(table: "vendor_invoice") { t in
                t.column("id", .text).primaryKey()
                t.column("vendor_id", .text).notNull()
                    .references("vendor", column: "id", onDelete: .cascade)
                t.column("invoice_date", .datetime).notNull()
                t.column("year", .integer).notNull()
                t.column("amount_cents", .integer).notNull().defaults(to: 0)
                t.column("vendor_invoice_number", .text).notNull().defaults(to: "")
                t.column("memo", .text).notNull().defaults(to: "")
                t.column("created_at", .datetime).notNull()
            }
            try db.create(index: "idx_vendor_invoice_vendor_year",
                          on: "vendor_invoice", columns: ["vendor_id", "year"])

            try db.create(table: "vendor_note") { t in
                t.column("id", .text).primaryKey()
                t.column("vendor_id", .text).notNull()
                    .references("vendor", column: "id", onDelete: .cascade)
                t.column("body_md", .text).notNull().defaults(to: "")
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(index: "idx_vendor_note_vendor",
                          on: "vendor_note", columns: ["vendor_id"])

            // Vendor attachments live in their own table (separate from the
            // matter-keyed `attachment` table) — keeps cascades and schemas
            // tidy. `parent_id` links invoice / note attachments back to their
            // owning row so deleting the row also drops the file.
            try db.create(table: "vendor_attachment") { t in
                t.column("id", .text).primaryKey()
                t.column("vendor_id", .text).notNull()
                    .references("vendor", column: "id", onDelete: .cascade)
                t.column("kind", .text).notNull()       // contract|invoice|note|other
                t.column("parent_id", .text)            // FK to vendor_invoice.id / vendor_note.id
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
            try db.create(index: "idx_vendor_attachment_vendor_kind",
                          on: "vendor_attachment", columns: ["vendor_id", "kind"])
            try db.create(index: "idx_vendor_attachment_parent",
                          on: "vendor_attachment", columns: ["parent_id"])

            // Optional FK from Matter → Vendor. `ON DELETE SET NULL` so
            // hard-deleting a vendor doesn't take its linked matters with it
            // (we only soft-delete in normal use anyway).
            try db.alter(table: "matter") { t in
                t.add(column: "vendor_id", .text)
                    .references("vendor", column: "id", onDelete: .setNull)
            }
            try db.create(index: "idx_matter_vendor", on: "matter", columns: ["vendor_id"])
        }

        migrator.registerMigration("v7_vendor_budget_code") { db in
            try db.alter(table: "vendor") { t in
                t.add(column: "budget_code", .text).notNull().defaults(to: "")
            }
        }

        migrator.registerMigration("v8_notes_workspace") { db in
            try db.create(table: "note_type") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("created_at", .datetime).notNull()
                t.uniqueKey(["name"])
            }
            try db.create(table: "generic_note") { t in
                t.column("id", .text).primaryKey()
                t.column("type_id", .text).notNull()
                    .references("note_type", column: "id", onDelete: .restrict)
                t.column("note_date", .date).notNull()
                t.column("title", .text).notNull().defaults(to: "")
                t.column("body_rtf", .blob)
                t.column("body_plain", .text).notNull().defaults(to: "")
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("deleted_at", .datetime)
            }
            try db.create(index: "idx_generic_note_type_date",
                          on: "generic_note", columns: ["type_id", "note_date"])
            try db.create(index: "idx_generic_note_deleted_at",
                          on: "generic_note", columns: ["deleted_at"])

            // Seed default types — the user can rename/delete/add via Settings.
            let defaults = ["Staff", "Architecture", "Team", "SCRUM", "Third Party"]
            for (i, name) in defaults.enumerated() {
                try db.execute(
                    sql: """
                    INSERT INTO note_type (id, name, sort_order, created_at)
                    VALUES (?, ?, ?, ?)
                    """,
                    arguments: [UUID().uuidString, name, i, Date()]
                )
            }
        }

        try migrator.migrate(writer)
    }

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
            let initCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM initiative") ?? 0
            if initCount == 0 {
                for (i, name) in Initiative.seedNames.enumerated() {
                    var row = Initiative(id: UUID().uuidString, name: name, sortOrder: i)
                    try row.insert(db)
                }
            }
            let goalCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM goal") ?? 0
            if goalCount == 0 {
                for (i, name) in Goal.seedNames.enumerated() {
                    var row = Goal(id: UUID().uuidString, name: name, sortOrder: i)
                    try row.insert(db)
                }
            }
        }
    }

    // MARK: - Matter

    func fetchAllMatters() throws -> [Matter] {
        try dbPool.read { db in
            // Live (non-trashed) Matters only. Trash is fetched separately
            // via `fetchTrashedMatters` so it never leaks into the main list.
            try Matter
                .filter(Column("deleted_at") == nil)
                .order(Column("modified_at").desc)
                .fetchAll(db)
        }
    }

    /// Trash bin contents — Matters with `deleted_at` set, newest first.
    func fetchTrashedMatters() throws -> [Matter] {
        try dbPool.read { db in
            try Matter
                .filter(Column("deleted_at") != nil)
                .order(Column("deleted_at").desc)
                .fetchAll(db)
        }
    }

    /// Hard-delete every Matter whose `deleted_at` is older than `cutoff`.
    /// Cascades clear all owned rows (subtasks, time entries, attachments…).
    @discardableResult
    func purgeTrashOlderThan(_ cutoff: Date) throws -> Int {
        try dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM matter WHERE deleted_at IS NOT NULL AND deleted_at < ?",
                arguments: [cutoff]
            )
            return db.changesCount
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

    // MARK: - Initiatives

    func fetchAllInitiatives() throws -> [Initiative] {
        try dbPool.read { db in
            try Initiative.order(Column("sort_order").asc).fetchAll(db)
        }
    }

    func saveInitiative(_ i: Initiative) throws {
        try dbPool.write { db in var row = i; try row.save(db) }
    }

    func deleteInitiative(id: String) throws {
        try dbPool.write { db in _ = try Initiative.deleteOne(db, key: id) }
    }

    // MARK: - Goals

    func fetchAllGoals() throws -> [Goal] {
        try dbPool.read { db in
            try Goal.order(Column("sort_order").asc).fetchAll(db)
        }
    }

    func saveGoal(_ g: Goal) throws {
        try dbPool.write { db in var row = g; try row.save(db) }
    }

    func deleteGoal(id: String) throws {
        try dbPool.write { db in _ = try Goal.deleteOne(db, key: id) }
    }

    // MARK: - Matter ↔ Initiative / Goal joins

    /// All `(matter_id, initiative_id)` pairs — used to populate the in-memory
    /// `matterInitiativeIds` map on AppState in a single read.
    func fetchAllMatterInitiativeLinks() throws -> [(matterId: String, initiativeId: String)] {
        try dbPool.read { db in
            try Row.fetchAll(db, sql: "SELECT matter_id, initiative_id FROM matter_initiative")
                .map { ($0["matter_id"], $0["initiative_id"]) }
        }
    }

    func fetchAllMatterGoalLinks() throws -> [(matterId: String, goalId: String)] {
        try dbPool.read { db in
            try Row.fetchAll(db, sql: "SELECT matter_id, goal_id FROM matter_goal")
                .map { ($0["matter_id"], $0["goal_id"]) }
        }
    }

    /// Replace the full set of initiatives linked to `matterId`. Single
    /// transaction so partial failures can't leave a half-tagged row.
    func setInitiatives(matterId: String, initiativeIds: Set<String>) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM matter_initiative WHERE matter_id = ?", arguments: [matterId])
            for iid in initiativeIds {
                try db.execute(
                    sql: "INSERT INTO matter_initiative (matter_id, initiative_id) VALUES (?, ?)",
                    arguments: [matterId, iid]
                )
            }
        }
    }

    func setGoals(matterId: String, goalIds: Set<String>) throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM matter_goal WHERE matter_id = ?", arguments: [matterId])
            for gid in goalIds {
                try db.execute(
                    sql: "INSERT INTO matter_goal (matter_id, goal_id) VALUES (?, ?)",
                    arguments: [matterId, gid]
                )
            }
        }
    }

    /// Copy initiative + goal tags from `sourceMatterId` to `destMatterId`.
    /// Used by cadence spawn so the next instance carries the same tags.
    func copyMatterTags(from sourceMatterId: String, to destMatterId: String) throws {
        try dbPool.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO matter_initiative (matter_id, initiative_id)
                SELECT ?, initiative_id FROM matter_initiative WHERE matter_id = ?
                """, arguments: [destMatterId, sourceMatterId])
            try db.execute(sql: """
                INSERT OR IGNORE INTO matter_goal (matter_id, goal_id)
                SELECT ?, goal_id FROM matter_goal WHERE matter_id = ?
                """, arguments: [destMatterId, sourceMatterId])
        }
    }

    // MARK: - Subtasks

    func fetchSubtasks(matterId: String) throws -> [Subtask] {
        try dbPool.read { db in
            try Subtask
                .filter(Column("matter_id") == matterId)
                .order(Column("sort_order").asc, Column("created_at").asc)
                .fetchAll(db)
        }
    }
    func upsertSubtask(_ s: Subtask) throws {
        try dbPool.write { db in var x = s; try x.save(db) }
    }
    func deleteSubtask(id: String) throws {
        try dbPool.write { db in _ = try Subtask.deleteOne(db, key: id) }
    }
    /// Aggregate (done, total) counts per matter for the list-row badge.
    func fetchSubtaskCounts() throws -> [String: (done: Int, total: Int)] {
        try dbPool.read { db in
            var out: [String: (done: Int, total: Int)] = [:]
            let rows = try Row.fetchAll(db, sql: """
                SELECT matter_id,
                       SUM(done)  AS d,
                       COUNT(*)   AS t
                FROM subtask GROUP BY matter_id
                """)
            for r in rows {
                let m: String = r["matter_id"]
                let d: Int    = r["d"] ?? 0
                let t: Int    = r["t"] ?? 0
                out[m] = (d, t)
            }
            return out
        }
    }

    // MARK: - Matter links

    func fetchAllLinks() throws -> [MatterLink] {
        try dbPool.read { db in try MatterLink.fetchAll(db) }
    }
    func upsertLink(_ l: MatterLink) throws {
        try dbPool.write { db in var x = l; try x.save(db) }
    }
    func deleteLink(matterId: String, related: String, kind: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM matter_link WHERE matter_id = ? AND related_matter_id = ? AND kind = ?",
                arguments: [matterId, related, kind]
            )
        }
    }

    // MARK: - Audit events

    func fetchAuditEvents(matterId: String) throws -> [AuditEvent] {
        try dbPool.read { db in
            try AuditEvent
                .filter(Column("matter_id") == matterId)
                .order(Column("ts").desc)
                .fetchAll(db)
        }
    }
    func appendAuditEvent(_ e: AuditEvent) throws {
        try dbPool.write { db in var x = e; try x.insert(db) }
    }

    // MARK: - Saved searches

    func fetchAllSavedSearches() throws -> [SavedSearch] {
        try dbPool.read { db in
            try SavedSearch.order(Column("sort_order").asc, Column("name").asc).fetchAll(db)
        }
    }
    func upsertSavedSearch(_ s: SavedSearch) throws {
        try dbPool.write { db in var x = s; try x.save(db) }
    }
    func deleteSavedSearch(id: String) throws {
        try dbPool.write { db in _ = try SavedSearch.deleteOne(db, key: id) }
    }
}
