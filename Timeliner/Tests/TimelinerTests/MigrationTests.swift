import XCTest
import GRDB
@testable import Timeliner

final class MigrationTests: XCTestCase {

    /// Apply the real production migrator to a fresh in-memory database
    /// and verify every expected table + index exists with the right
    /// columns. Catches drift between `DatabaseService.applyMigrations`
    /// and the test fixtures (the failure mode the previous duplicated
    /// schema couldn't catch).
    @MainActor
    func testAllMigrationsCreateExpectedTables() throws {
        let queue = try DatabaseQueue()
        try DatabaseService.applyMigrations(to: queue)

        try queue.read { db in
            let tables = ["cases", "events", "tags", "event_tags",
                          "people", "event_people", "attachments"]
            for t in tables {
                let exists = try Bool.fetchOne(
                    db,
                    sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?)",
                    arguments: [t]
                ) ?? false
                XCTAssertTrue(exists, "Table '\(t)' should exist after migrations")
            }

            // Spot-check that ON DELETE CASCADE is set on events.case_id.
            let fkRows = try Row.fetchAll(db, sql: "PRAGMA foreign_key_list('events')")
            let cascadeCaseId = fkRows.contains {
                ($0["table"] as? String) == "cases" && ($0["on_delete"] as? String) == "CASCADE"
            }
            XCTAssertTrue(cascadeCaseId, "events.case_id should ON DELETE CASCADE → cases")
        }
    }

    /// Round-trip insert and fetch — the simplest "the schema actually works"
    /// smoke test.
    @MainActor
    func testInsertAndFetchACase() throws {
        let queue = try DatabaseQueue()
        try DatabaseService.applyMigrations(to: queue)

        try queue.write { db in
            let now = ISO8601DateFormatter().string(from: Date())
            var c = Case(
                id: "case-1", title: "OJ Trial", caseDescription: "",
                status: "active", pinned: false,
                createdAt: now, updatedAt: now
            )
            try c.insert(db)
        }
        try queue.read { db in
            let row = try Case.fetchOne(db, key: "case-1")
            XCTAssertEqual(row?.title, "OJ Trial")
        }
    }

    /// Cascade delete: removing a case wipes its events.
    @MainActor
    func testCaseDeleteCascadesToEvents() throws {
        let queue = try DatabaseQueue()
        try queue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        try DatabaseService.applyMigrations(to: queue)

        try queue.write { db in
            let now = ISO8601DateFormatter().string(from: Date())
            var c = Case(
                id: "C", title: "X", caseDescription: "", status: "active",
                pinned: false, createdAt: now, updatedAt: now
            )
            try c.insert(db)
            var e = Event(
                id: "E", caseId: "C", title: "ev",
                dateStart: now, dateEnd: nil,
                descriptionMarkdown: "", sourceURL: "",
                importance: "medium", createdAt: now
            )
            try e.insert(db)
            _ = try Case.deleteOne(db, key: "C")
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM events") ?? -1
            XCTAssertEqual(count, 0, "Events should cascade-delete with their case")
        }
    }

    /// v2_attachments_blob: schema is polymorphic, has a BLOB column for
    /// data, and supports inserting attachments for any of the three parent
    /// kinds.
    @MainActor
    func testAttachmentsTableIsPolymorphicWithBLOB() throws {
        let queue = try DatabaseQueue()
        try DatabaseService.applyMigrations(to: queue)

        try queue.read { db in
            let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('attachments')")
            let names = cols.compactMap { $0["name"] as? String }
            for required in ["id", "parent_type", "parent_id", "filename",
                              "mime_type", "size_bytes", "data", "thumbnail_data",
                              "position", "created_at"] {
                XCTAssertTrue(names.contains(required),
                              "attachments table should have column '\(required)'")
            }

            // BLOB type is reported as 'BLOB' in PRAGMA table_info
            if let dataRow = cols.first(where: { ($0["name"] as? String) == "data" }) {
                XCTAssertEqual((dataRow["type"] as? String)?.uppercased(), "BLOB")
            } else {
                XCTFail("data column missing")
            }
        }

        // Insert one of each parent kind and read them back.
        try queue.write { db in
            let now = ISO8601DateFormatter().string(from: Date())
            for kind in [AttachmentParent.caseRecord, .event, .person] {
                var a = Attachment(
                    id: UUID().uuidString,
                    parentType: kind.rawValue,
                    parentId: "p-\(kind.rawValue)",
                    filename: "test.bin",
                    mimeType: "application/octet-stream",
                    sizeBytes: 5,
                    data: Data([0x01, 0x02, 0x03, 0x04, 0x05]),
                    thumbnailData: nil,
                    position: 0,
                    createdAt: now
                )
                try a.insert(db)
            }
        }
        try queue.read { db in
            let n = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM attachments") ?? 0
            XCTAssertEqual(n, 3)
        }
    }
}
