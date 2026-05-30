import XCTest
import GRDB
@testable import PurpleDiary

final class MigrationTests: XCTestCase {

    /// Apply the real production migrator to a fresh in-memory database and
    /// verify every expected table exists. Catches drift between
    /// `DatabaseService.applyMigrations` and the schema the app assumes.
    @MainActor
    func testAllMigrationsCreateExpectedTables() throws {
        let queue = try DatabaseQueue()
        try DatabaseService.applyMigrations(to: queue)

        try queue.read { db in
            let tables = ["entries", "tags", "entry_tags", "people", "entry_people"]
            for t in tables {
                let exists = try Bool.fetchOne(
                    db,
                    sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?)",
                    arguments: [t]
                ) ?? false
                XCTAssertTrue(exists, "Table '\(t)' should exist after migrations")
            }

            // entry_tags.entry_id should ON DELETE CASCADE → entries.
            let fkRows = try Row.fetchAll(db, sql: "PRAGMA foreign_key_list('entry_tags')")
            let cascade = fkRows.contains {
                ($0["table"] as? String) == "entries" && ($0["on_delete"] as? String) == "CASCADE"
            }
            XCTAssertTrue(cascade, "entry_tags.entry_id should ON DELETE CASCADE → entries")
        }
    }

    /// Round-trip insert and fetch — the simplest "the schema works" smoke test.
    @MainActor
    func testInsertAndFetchAnEntry() throws {
        let queue = try DatabaseQueue()
        try DatabaseService.applyMigrations(to: queue)

        try queue.write { db in
            var e = Entry.newDraft(title: "First light")
            e.id = "entry-1"
            try e.insert(db)
        }
        try queue.read { db in
            let row = try Entry.fetchOne(db, key: "entry-1")
            XCTAssertEqual(row?.title, "First light")
        }
    }

    /// Deleting an entry cascades its tag links but not the tags themselves.
    @MainActor
    func testEntryDeleteCascadesToEntryTags() throws {
        let queue = try DatabaseQueue()
        try queue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        try DatabaseService.applyMigrations(to: queue)

        try queue.write { db in
            var e = Entry.newDraft(title: "x")
            e.id = "E"
            try e.insert(db)
            var t = Tag(rowId: nil, name: "work", colorHex: "#3FA9F5")
            try t.insert(db)
            let link = EntryTag(entryId: "E", tagId: t.rowId!)
            try link.insert(db)

            _ = try Entry.deleteOne(db, key: "E")

            let linkCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entry_tags") ?? -1
            let tagCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags") ?? -1
            XCTAssertEqual(linkCount, 0, "entry_tags should cascade-delete with the entry")
            XCTAssertEqual(tagCount, 1, "the tag itself should survive")
        }
    }
}
