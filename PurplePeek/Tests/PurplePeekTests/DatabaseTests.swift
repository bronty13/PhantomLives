import XCTest
import GRDB
@testable import PurplePeek

@MainActor
final class DatabaseTests: XCTestCase {

    /// Apply the real production migrator to a fresh in-memory database.
    private func migratedQueue() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try DatabaseService.applyMigrations(to: queue)
        return queue
    }

    func testMigrationCreatesAllTables() throws {
        let queue = try migratedQueue()
        let tables = try queue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        }
        for expected in ["file_albums", "file_keywords", "keywords", "media_files", "scan_roots"] {
            XCTAssertTrue(tables.contains(expected), "missing table \(expected)")
        }
    }

    /// Immutability guard: the shipped migration ledger must stay exactly this. Adding a new
    /// migration updates this list intentionally; editing/removing v1_initial fails here.
    func testMigrationLedgerIsFrozen() throws {
        let queue = try migratedQueue()
        let ids = try queue.read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
        }
        XCTAssertEqual(ids, ["v1_initial"])
    }

    func testMediaFileRoundTrip() throws {
        let queue = try migratedQueue()
        try queue.write { db in
            var root = ScanRoot(path: "/tmp/r", lastScannedAt: "2026-01-01T00:00:00", totalFiles: 1, label: nil)
            try root.insert(db)
            var file = MediaFile(
                id: "f1", scanRoot: "/tmp/r", filePath: "/tmp/r/a.jpg", fileName: "a.jpg",
                fileType: "photo", fileSize: 123, fileModifiedAt: nil, keep: 1, isFavorite: true,
                title: "T", caption: "C", importedAt: nil, exportedAt: nil, deletedAt: nil,
                photosAssetId: nil, createdAt: "2026-01-01T00:00:00", updatedAt: "2026-01-01T00:00:00"
            )
            try file.insert(db)
        }
        let fetched = try queue.read { db in try MediaFile.fetchOne(db, key: "f1") }
        XCTAssertEqual(fetched?.fileName, "a.jpg")
        XCTAssertEqual(fetched?.mediaType, .photo)
        XCTAssertEqual(fetched?.keepDecision, true)        // keep=1 → true
        XCTAssertTrue(fetched?.isFavorite ?? false)
        XCTAssertEqual(fetched?.title, "T")
        XCTAssertEqual(fetched?.fileSize, 123)
    }

    func testKeepTriState() {
        var f = MediaFile(id: "x", scanRoot: "/r", filePath: "/r/x", fileName: "x", fileType: "photo",
                          fileSize: nil, fileModifiedAt: nil, keep: nil, isFavorite: false, title: nil,
                          caption: nil, importedAt: nil, exportedAt: nil, deletedAt: nil,
                          photosAssetId: nil, createdAt: "", updatedAt: "")
        XCTAssertNil(f.keepDecision)        // undecided
        f.keepDecision = false
        XCTAssertEqual(f.keep, 0)
        f.keepDecision = true
        XCTAssertEqual(f.keep, 1)
        f.keepDecision = nil
        XCTAssertNil(f.keep)
    }

    /// The re-scan upsert must refresh on-disk metadata but preserve decisions + scan_root.
    func testUpsertPreservesDecisions() throws {
        let queue = try migratedQueue()
        try queue.write { db in
            try db.execute(sql: "INSERT INTO scan_roots(path,last_scanned_at,total_files) VALUES('/r','t',0)")
            // First discovery
            try db.execute(sql: """
                INSERT INTO media_files(id,scan_root,file_path,file_name,file_type,file_size,is_favorite,created_at,updated_at)
                VALUES('id1','/r','/r/a.jpg','a.jpg','photo',100,0,'t','t')
                """)
            // User decisions
            try db.execute(sql: "UPDATE media_files SET keep=1, is_favorite=1, title='Keep me' WHERE id='id1'")
            // Re-scan upsert (same path, new uuid + new size) — mirrors upsertScannedFiles
            try db.execute(sql: """
                INSERT INTO media_files(id,scan_root,file_path,file_name,file_type,file_size,is_favorite,created_at,updated_at)
                VALUES('id2','/r','/r/a.jpg','a.jpg','photo',999,0,'t2','t2')
                ON CONFLICT(file_path) DO UPDATE SET
                  file_name=excluded.file_name, file_type=excluded.file_type,
                  file_size=excluded.file_size, updated_at=excluded.updated_at
                """)
        }
        let f = try queue.read { db in try MediaFile.filter(Column("file_path") == "/r/a.jpg").fetchOne(db) }
        XCTAssertEqual(f?.id, "id1")            // original row kept (not the new uuid)
        XCTAssertEqual(f?.keepDecision, true)   // decision preserved
        XCTAssertTrue(f?.isFavorite ?? false)
        XCTAssertEqual(f?.title, "Keep me")
        XCTAssertEqual(f?.fileSize, 999)        // metadata refreshed
    }

    func testCascadeDeleteOfScanRoot() throws {
        let queue = try migratedQueue()
        try queue.write { db in
            try db.execute(sql: "INSERT INTO scan_roots(path,last_scanned_at,total_files) VALUES('/r','t',0)")
            try db.execute(sql: """
                INSERT INTO media_files(id,scan_root,file_path,file_name,file_type,is_favorite,created_at,updated_at)
                VALUES('m1','/r','/r/a.jpg','a.jpg','photo',0,'t','t')
                """)
            try db.execute(sql: "INSERT INTO keywords(id,name,source,created_at) VALUES('k1','Sun','local','t')")
            try db.execute(sql: "INSERT INTO file_keywords(file_id,keyword_id) VALUES('m1','k1')")
            try db.execute(sql: "INSERT INTO file_albums(file_id,album_name) VALUES('m1','Trip')")
            try db.execute(sql: "DELETE FROM scan_roots WHERE path='/r'")
        }
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM media_files"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM file_keywords"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM file_albums"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM keywords"), 1) // keyword vocab kept
        }
    }
}
