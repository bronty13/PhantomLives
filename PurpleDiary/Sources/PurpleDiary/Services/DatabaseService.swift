import Foundation
import GRDB

/// Sole owner of the GRDB `DatabasePool` for `diary.sqlite`. Runs the
/// append-only migrator at init and exposes thin per-record CRUD wrappers.
/// Migration logic lives in `static applyMigrations(to:)` so the test suite
/// applies the *real* migrator instead of a duplicated fixture — drift between
/// production schema and tests would defeat the migration tests.
///
/// **Migrations are immutable** (per CLAUDE.md): never edit a shipped
/// migration. Add a new `registerMigration` block instead.
@MainActor
final class DatabaseService {
    static let shared = DatabaseService()

    private(set) var dbPool: DatabasePool

    static var supportDirectory: URL { AppSettings.supportDirectory }

    var databaseURL: URL {
        Self.supportDirectory.appendingPathComponent("diary.sqlite")
    }

    private init() {
        let dir = Self.supportDirectory
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("diary.sqlite")
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
    /// `DatabaseQueue` instead of duplicating the migration body and drifting
    /// over time. Add new versions inside this function — never inside
    /// `init()` — to keep test coverage automatic.
    static func applyMigrations(to writer: DatabaseWriter) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "entries") { t in
                t.column("id", .text).primaryKey()
                t.column("date", .text).notNull()
                t.column("title", .text).notNull().defaults(to: "")
                t.column("body_markdown", .text).notNull().defaults(to: "")
                t.column("mood_rating", .integer).notNull().defaults(to: 0)
                t.column("word_count", .integer).notNull().defaults(to: 0)
                // Phase-2 auto-context columns — nullable, created now so the
                // import services don't need a follow-up migration.
                t.column("latitude", .double)
                t.column("longitude", .double)
                t.column("place_name", .text)
                t.column("weather_summary", .text)
                t.column("temperature_c", .double)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.create(index: "idx_entries_date", on: "entries", columns: ["date"])
            try db.create(index: "idx_entries_mood", on: "entries", columns: ["mood_rating"])

            try db.create(table: "tags") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().collate(.nocase)
                t.column("color_hex", .text).notNull().defaults(to: "#888888")
                t.uniqueKey(["name"])
            }

            try db.create(table: "entry_tags") { t in
                t.column("entry_id", .text).notNull()
                    .references("entries", column: "id", onDelete: .cascade)
                t.column("tag_id", .integer).notNull()
                    .references("tags", column: "id", onDelete: .cascade)
                t.primaryKey(["entry_id", "tag_id"])
            }

            try db.create(table: "people") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull().defaults(to: "")
                t.column("notes", .text).notNull().defaults(to: "")
            }

            try db.create(table: "entry_people") { t in
                t.column("entry_id", .text).notNull()
                    .references("entries", column: "id", onDelete: .cascade)
                t.column("person_id", .text).notNull()
                    .references("people", column: "id", onDelete: .cascade)
                t.primaryKey(["entry_id", "person_id"])
            }
        }

        try migrator.migrate(writer)
    }

    func seedDefaultTagsIfEmpty() throws {
        try dbPool.write { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags") ?? 0
            guard count == 0 else { return }
            let defaults: [(String, String)] = [
                ("personal", "#7C5CFF"),
                ("work",     "#3FA9F5"),
                ("travel",   "#3FB950"),
                ("health",   "#E8A93B"),
                ("ideas",    "#F08C2E"),
                ("gratitude","#D14B5C"),
            ]
            for (name, hex) in defaults {
                var tag = Tag(rowId: nil, name: name, colorHex: hex)
                try tag.insert(db)
            }
        }
    }

    // MARK: - Entries

    func fetchAllEntries() throws -> [Entry] {
        try dbPool.read { db in
            try Entry.order(Column("date").desc).fetchAll(db)
        }
    }

    func fetchEntry(id: String) throws -> Entry? {
        try dbPool.read { db in
            try Entry.fetchOne(db, key: id)
        }
    }

    func insertEntry(_ entry: Entry) throws {
        try dbPool.write { db in
            var mutable = entry
            mutable.refreshWordCount()
            try mutable.insert(db)
        }
    }

    func updateEntry(_ entry: Entry) throws {
        var stamped = entry
        stamped.updatedAt = Self.isoNow()
        stamped.refreshWordCount()
        try dbPool.write { db in
            try stamped.update(db)
        }
    }

    func deleteEntry(id: String) throws {
        try dbPool.write { db in
            _ = try Entry.deleteOne(db, key: id)
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

    func tagIDs(forEntry entryId: String) throws -> [Int64] {
        try dbPool.read { db in
            try Int64.fetchAll(
                db,
                sql: "SELECT tag_id FROM entry_tags WHERE entry_id = ?",
                arguments: [entryId]
            )
        }
    }

    func setTags(_ tagIds: [Int64], forEntry entryId: String) throws {
        try dbPool.write { db in
            try EntryTag.filter(Column("entry_id") == entryId).deleteAll(db)
            for tid in Set(tagIds) {
                let row = EntryTag(entryId: entryId, tagId: tid)
                try row.insert(db)
            }
        }
    }

    /// entry.id → [Tag], built from a single join query for the whole journal.
    func tagsByEntry() throws -> [String: [Tag]] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT et.entry_id AS entry_id, t.id AS id, t.name AS name, t.color_hex AS color_hex
                FROM entry_tags et
                JOIN tags t ON t.id = et.tag_id
                """)
            var out: [String: [Tag]] = [:]
            for row in rows {
                let eid: String = row["entry_id"]
                let tag = Tag(rowId: row["id"], name: row["name"], colorHex: row["color_hex"])
                out[eid, default: []].append(tag)
            }
            return out
        }
    }

    // MARK: - People

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

    func personIDs(forEntry entryId: String) throws -> [String] {
        try dbPool.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT person_id FROM entry_people WHERE entry_id = ?",
                arguments: [entryId]
            )
        }
    }

    func setPeople(_ personIds: [String], forEntry entryId: String) throws {
        try dbPool.write { db in
            try EntryPerson.filter(Column("entry_id") == entryId).deleteAll(db)
            for pid in Set(personIds) {
                let row = EntryPerson(entryId: entryId, personId: pid)
                try row.insert(db)
            }
        }
    }

    func peopleByEntry() throws -> [String: [Person]] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT ep.entry_id AS entry_id, p.id AS id, p.name AS name, p.notes AS notes
                FROM entry_people ep
                JOIN people p ON p.id = ep.person_id
                """)
            var out: [String: [Person]] = [:]
            for row in rows {
                let eid: String = row["entry_id"]
                let person = Person(id: row["id"], name: row["name"], notes: row["notes"])
                out[eid, default: []].append(person)
            }
            return out
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
