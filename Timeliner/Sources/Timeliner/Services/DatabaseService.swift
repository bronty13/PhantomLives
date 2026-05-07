import Foundation
import GRDB

@MainActor
final class DatabaseService {
    static let shared = DatabaseService()

    private(set) var dbPool: DatabasePool

    static var supportDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Timeliner", isDirectory: true)
    }

    var databaseURL: URL {
        Self.supportDirectory.appendingPathComponent("timeliner.sqlite")
    }

    var attachmentsDirectory: URL {
        Self.supportDirectory.appendingPathComponent("attachments", isDirectory: true)
    }

    private init() {
        let dir = Self.supportDirectory
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let attDir = dir.appendingPathComponent("attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: attDir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("timeliner.sqlite")
        dbPool = try! DatabasePool(path: dbURL.path)
        try! migrate()
        try? seedDefaults()
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
    /// `DatabaseQueue` instead of duplicating the migration body and drifting
    /// over time. Add new versions inside this function — never inside
    /// `init()` — to keep test coverage automatic.
    static func applyMigrations(to writer: DatabaseWriter) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "cases") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull().defaults(to: "")
                t.column("description", .text).notNull().defaults(to: "")
                t.column("status", .text).notNull().defaults(to: "active")
                t.column("pinned", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.create(index: "idx_cases_status",  on: "cases", columns: ["status"])
            try db.create(index: "idx_cases_pinned",  on: "cases", columns: ["pinned"])

            try db.create(table: "events") { t in
                t.column("id", .text).primaryKey()
                t.column("case_id", .text).notNull()
                    .references("cases", column: "id", onDelete: .cascade)
                t.column("title", .text).notNull().defaults(to: "")
                t.column("date_start", .text).notNull()
                t.column("date_end", .text)
                t.column("description_markdown", .text).notNull().defaults(to: "")
                t.column("source_url", .text).notNull().defaults(to: "")
                t.column("importance", .text).notNull().defaults(to: "medium")
                t.column("created_at", .text).notNull()
            }
            try db.create(index: "idx_events_case",        on: "events", columns: ["case_id"])
            try db.create(index: "idx_events_date_start",  on: "events", columns: ["date_start"])
            try db.create(index: "idx_events_importance",  on: "events", columns: ["importance"])

            try db.create(table: "tags") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().collate(.nocase)
                t.column("color_hex", .text).notNull().defaults(to: "#888888")
                t.uniqueKey(["name"])
            }

            try db.create(table: "event_tags") { t in
                t.column("event_id", .text).notNull()
                    .references("events", column: "id", onDelete: .cascade)
                t.column("tag_id", .integer).notNull()
                    .references("tags", column: "id", onDelete: .cascade)
                t.primaryKey(["event_id", "tag_id"])
            }

            try db.create(table: "people") { t in
                t.column("id", .text).primaryKey()
                t.column("case_id", .text).notNull()
                    .references("cases", column: "id", onDelete: .cascade)
                t.column("name", .text).notNull().defaults(to: "")
                t.column("role", .text).notNull().defaults(to: "other")
                t.column("notes", .text).notNull().defaults(to: "")
            }
            try db.create(index: "idx_people_case", on: "people", columns: ["case_id"])

            try db.create(table: "event_people") { t in
                t.column("event_id", .text).notNull()
                    .references("events", column: "id", onDelete: .cascade)
                t.column("person_id", .text).notNull()
                    .references("people", column: "id", onDelete: .cascade)
                t.column("role_in_event", .text)
                t.primaryKey(["event_id", "person_id"])
            }

            // Phase-2 schema (table created now so attachments can be persisted
            // alongside future UI without a follow-up migration).
            try db.create(table: "attachments") { t in
                t.column("id", .text).primaryKey()
                t.column("event_id", .text).notNull()
                    .references("events", column: "id", onDelete: .cascade)
                t.column("filename", .text).notNull()
                t.column("mime_type", .text).notNull().defaults(to: "application/octet-stream")
                t.column("size_bytes", .integer).notNull().defaults(to: 0)
                t.column("sha256", .text).notNull()
                t.column("created_at", .text).notNull()
            }
            try db.create(index: "idx_attachments_event", on: "attachments", columns: ["event_id"])
        }

        // v2 — pivot attachments from per-event-on-disk-sha256 to polymorphic
        // BLOBs in the database. The Phase 1 attachments UI never shipped, so
        // the v1 table is empty in every user's DB and a clean drop+recreate
        // is safe (no data to preserve). After v2 the table is shared across
        // case / event / person parents via parent_type + parent_id.
        migrator.registerMigration("v2_attachments_blob") { db in
            if try db.tableExists("attachments") {
                try db.drop(table: "attachments")
            }
            try db.create(table: "attachments") { t in
                t.column("id", .text).primaryKey()
                t.column("parent_type", .text).notNull()  // 'case' | 'event' | 'person'
                t.column("parent_id", .text).notNull()
                t.column("filename", .text).notNull()
                t.column("mime_type", .text).notNull().defaults(to: "application/octet-stream")
                t.column("size_bytes", .integer).notNull().defaults(to: 0)
                t.column("data", .blob).notNull()
                t.column("thumbnail_data", .blob)
                t.column("position", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).notNull()
            }
            try db.create(
                index: "idx_attachments_parent",
                on: "attachments",
                columns: ["parent_type", "parent_id"]
            )
        }

        try migrator.migrate(writer)
    }

    private func seedDefaults() throws {
        try dbPool.write { db in
            // Only seed if the tags table is empty — never touch user tags.
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags") ?? 0
            guard count == 0 else { return }

            let defaults: [(String, String)] = [
                ("evidence",  "#E8A93B"),
                ("witness",   "#3FA9F5"),
                ("suspect",   "#D14B5C"),
                ("court",     "#9D4DCC"),
                ("scene",     "#3FB950"),
                ("media",     "#F08C2E"),
            ]
            for (name, hex) in defaults {
                var tag = Tag(rowId: nil, name: name, colorHex: hex)
                try tag.insert(db)
            }
        }
    }

    // MARK: - Cases

    func fetchAllCases() throws -> [Case] {
        try dbPool.read { db in
            try Case.order(
                Column("pinned").desc,
                Column("updated_at").desc
            ).fetchAll(db)
        }
    }

    func fetchCase(id: String) throws -> Case? {
        try dbPool.read { db in
            try Case.fetchOne(db, key: id)
        }
    }

    func insertCase(_ aCase: Case) throws {
        try dbPool.write { db in
            var mutable = aCase
            try mutable.insert(db)
        }
    }

    func updateCase(_ aCase: Case) throws {
        var stamped = aCase
        stamped.updatedAt = Self.isoNow()
        try dbPool.write { db in
            try stamped.update(db)
        }
    }

    func deleteCase(id: String) throws {
        try dbPool.write { db in
            _ = try Case.deleteOne(db, key: id)
        }
    }

    // MARK: - Events

    func fetchEvents(caseId: String) throws -> [Event] {
        try dbPool.read { db in
            try Event
                .filter(Column("case_id") == caseId)
                .order(Column("date_start").asc)
                .fetchAll(db)
        }
    }

    func fetchAllEvents() throws -> [Event] {
        try dbPool.read { db in
            try Event.order(Column("date_start").asc).fetchAll(db)
        }
    }

    func fetchEvents(caseId: String, dateStartGE: String?, dateStartLE: String?) throws -> [Event] {
        try dbPool.read { db in
            var q = Event.filter(Column("case_id") == caseId)
            if let lo = dateStartGE { q = q.filter(Column("date_start") >= lo) }
            if let hi = dateStartLE { q = q.filter(Column("date_start") <= hi) }
            return try q.order(Column("date_start").asc).fetchAll(db)
        }
    }

    func insertEvent(_ event: Event) throws {
        try dbPool.write { db in
            var mutable = event
            try mutable.insert(db)
        }
    }

    func updateEvent(_ event: Event) throws {
        try dbPool.write { db in
            try event.update(db)
        }
    }

    func deleteEvent(id: String) throws {
        try dbPool.write { db in
            _ = try Event.deleteOne(db, key: id)
        }
    }

    // MARK: - Tags

    func fetchAllTags() throws -> [Tag] {
        try dbPool.read { db in
            try Tag.order(Column("name").asc).fetchAll(db)
        }
    }

    func saveTag(_ tag: inout Tag) throws {
        try dbPool.write { db in
            try tag.save(db)
        }
    }

    func deleteTag(id: Int64) throws {
        try dbPool.write { db in
            _ = try Tag.deleteOne(db, key: id)
        }
    }

    func tagIDs(forEvent eventId: String) throws -> [Int64] {
        try dbPool.read { db in
            try Int64.fetchAll(
                db,
                sql: "SELECT tag_id FROM event_tags WHERE event_id = ?",
                arguments: [eventId]
            )
        }
    }

    func setTags(_ tagIds: [Int64], forEvent eventId: String) throws {
        try dbPool.write { db in
            try EventTag.filter(Column("event_id") == eventId).deleteAll(db)
            for tid in Set(tagIds) {
                let row = EventTag(eventId: eventId, tagId: tid)
                try row.insert(db)
            }
        }
    }

    func tagsByEvent(in caseId: String) throws -> [String: [Tag]] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT et.event_id AS event_id, t.id AS id, t.name AS name, t.color_hex AS color_hex
                FROM event_tags et
                JOIN tags t ON t.id = et.tag_id
                JOIN events e ON e.id = et.event_id
                WHERE e.case_id = ?
                """, arguments: [caseId])
            var out: [String: [Tag]] = [:]
            for row in rows {
                let eid: String = row["event_id"]
                let tag = Tag(rowId: row["id"], name: row["name"], colorHex: row["color_hex"])
                out[eid, default: []].append(tag)
            }
            return out
        }
    }

    // MARK: - People

    func fetchPeople(caseId: String) throws -> [Person] {
        try dbPool.read { db in
            try Person
                .filter(Column("case_id") == caseId)
                .order(Column("name").asc)
                .fetchAll(db)
        }
    }

    func fetchAllPeople() throws -> [Person] {
        try dbPool.read { db in
            try Person.order(Column("name").asc).fetchAll(db)
        }
    }

    func savePerson(_ p: Person) throws {
        try dbPool.write { db in
            var mutable = p
            try mutable.save(db)
        }
    }

    func deletePerson(id: String) throws {
        try dbPool.write { db in
            _ = try Person.deleteOne(db, key: id)
        }
    }

    func personIDs(forEvent eventId: String) throws -> [String] {
        try dbPool.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT person_id FROM event_people WHERE event_id = ?",
                arguments: [eventId]
            )
        }
    }

    func setPeople(_ personIds: [String], forEvent eventId: String) throws {
        try dbPool.write { db in
            try EventPerson.filter(Column("event_id") == eventId).deleteAll(db)
            for pid in Set(personIds) {
                let row = EventPerson(eventId: eventId, personId: pid, roleInEvent: nil)
                try row.insert(db)
            }
        }
    }

    // MARK: - Attachments (Phase 3 — polymorphic BLOB)

    func fetchAttachments(parentType: AttachmentParent, parentId: String) throws -> [Attachment] {
        try dbPool.read { db in
            try Attachment
                .filter(Column("parent_type") == parentType.rawValue
                        && Column("parent_id") == parentId)
                .order(Column("position").asc, Column("created_at").asc)
                .fetchAll(db)
        }
    }

    /// Lighter-weight variant that skips the data + thumbnail BLOBs. Used
    /// by list/badge UI that just needs to know "does X have N attachments
    /// of type Y" without paging tens of megabytes in.
    func fetchAttachmentMetadata(parentType: AttachmentParent, parentId: String) throws -> [(id: String, filename: String, mimeType: String, sizeBytes: Int64)] {
        try dbPool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, filename, mime_type, size_bytes
                FROM attachments
                WHERE parent_type = ? AND parent_id = ?
                ORDER BY position ASC, created_at ASC
                """, arguments: [parentType.rawValue, parentId])
            .map { row in
                (
                    id: row["id"] as String,
                    filename: row["filename"] as String,
                    mimeType: row["mime_type"] as String,
                    sizeBytes: row["size_bytes"] as Int64
                )
            }
        }
    }

    func attachmentCounts(parentType: AttachmentParent) throws -> [String: Int] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT parent_id, COUNT(*) AS c
                FROM attachments
                WHERE parent_type = ?
                GROUP BY parent_id
                """, arguments: [parentType.rawValue])
            var out: [String: Int] = [:]
            for row in rows {
                out[row["parent_id"]] = row["c"]
            }
            return out
        }
    }

    func insertAttachment(_ a: Attachment) throws {
        try dbPool.write { db in
            var mutable = a
            try mutable.insert(db)
        }
    }

    /// Updates only renames / position changes — never touches the BLOB
    /// payload, which is set once at insert time.
    func updateAttachment(_ a: Attachment) throws {
        try dbPool.write { db in
            try a.update(db)
        }
    }

    func deleteAttachment(id: String) throws {
        try dbPool.write { db in
            _ = try Attachment.deleteOne(db, key: id)
        }
    }

    /// Cascade delete attachments for a parent — used when the parent record
    /// is wiped (e.g., case delete). Cases/events/people don't have a real
    /// FK to attachments because of the polymorphic shape, so we have to
    /// do this manually from the AppState delete path.
    func deleteAttachments(parentType: AttachmentParent, parentId: String) throws {
        try dbPool.write { db in
            try db.execute(
                sql: "DELETE FROM attachments WHERE parent_type = ? AND parent_id = ?",
                arguments: [parentType.rawValue, parentId]
            )
        }
    }

    /// Total bytes consumed by the BLOB column. Surfaced in Settings →
    /// Backup so the user can decide whether attachments are bloating
    /// their backup zips.
    func attachmentTotalBytes() throws -> Int64 {
        try dbPool.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(size_bytes), 0) FROM attachments") ?? 0
        }
    }

    // MARK: - Counts (for sidebar badges)

    func eventCount(caseId: String) throws -> Int {
        try dbPool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM events WHERE case_id = ?",
                arguments: [caseId]
            ) ?? 0
        }
    }

    func personCount(caseId: String) throws -> Int {
        try dbPool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM people WHERE case_id = ?",
                arguments: [caseId]
            ) ?? 0
        }
    }

    // MARK: - Helpers

    static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    static func isoDate(_ d: Date) -> String {
        ISO8601DateFormatter().string(from: d)
    }
}
