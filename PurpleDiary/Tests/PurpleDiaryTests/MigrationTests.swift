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
            let tables = ["entries", "tags", "entry_tags", "people", "entry_people",
                          "tracker_tags", "tracker_values", "attachments"]
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

    /// Tracker values cascade-delete with both their entry and their tracker
    /// definition, but the entry/tracker on the other side survives.
    @MainActor
    func testTrackerValueCascades() throws {
        let queue = try DatabaseQueue()
        try queue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        try DatabaseService.applyMigrations(to: queue)

        try queue.write { db in
            var e = Entry.newDraft(title: "x"); e.id = "E"; try e.insert(db)
            var f = Entry.newDraft(title: "y"); f.id = "F"; try f.insert(db)
            var water = TrackerTag(rowId: nil, name: "Water", unit: "cups", kind: .number, colorHex: "#3FA9F5")
            try water.insert(db)
            try TrackerValue(entryId: "E", trackerTagId: water.rowId!, value: 6).insert(db)
            try TrackerValue(entryId: "F", trackerTagId: water.rowId!, value: 4).insert(db)

            // Deleting entry E removes only its tracker value.
            _ = try Entry.deleteOne(db, key: "E")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracker_values") ?? -1, 1,
                           "only E's value should cascade away")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracker_tags") ?? -1, 1,
                           "the tracker definition survives an entry delete")

            // Deleting the tracker definition removes all remaining values.
            _ = try TrackerTag.deleteOne(db, key: water.rowId!)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracker_values") ?? -1, 0,
                           "deleting the tracker cascades its values")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries") ?? -1, 1,
                           "entry F survives the tracker delete")
        }
    }

    /// Attachments cascade-delete with their entry; the row round-trips its
    /// BLOB through GRDB.
    @MainActor
    func testAttachmentInsertFetchAndCascade() throws {
        let queue = try DatabaseQueue()
        try queue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        try DatabaseService.applyMigrations(to: queue)

        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03])
        try queue.write { db in
            var e = Entry.newDraft(title: "with photo"); e.id = "E"; try e.insert(db)
            var a = Attachment(id: "A", entryId: "E", kind: "photo",
                               filename: "IMG_0001.jpg", mimeType: "image/jpeg",
                               sizeBytes: Int64(bytes.count), width: 4, height: 3,
                               data: bytes, thumbnailData: Data([0x01]),
                               sourceAssetId: "asset/1", createdAt: "2026-05-31T00:00:00Z")
            try a.insert(db)

            let back = try Attachment.fetchOne(db, key: "A")
            XCTAssertEqual(back?.data, bytes)
            XCTAssertEqual(back?.filename, "IMG_0001.jpg")
            XCTAssertEqual(back?.sourceAssetId, "asset/1")

            _ = try Entry.deleteOne(db, key: "E")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM attachments") ?? -1, 0,
                           "attachments cascade-delete with their entry")
        }
    }
}
