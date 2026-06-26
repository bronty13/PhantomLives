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
        XCTAssertEqual(ids, ["v1_initial", "v2_add_is_hidden", "v3_add_missing_at",
                             "v4_add_sidebar_sections", "v5_add_content_hash"])
    }

    /// Re-scan clears a stored content hash only when size/mtime changed (so unchanged files
    /// aren't needlessly re-hashed). Mirrors the `content_hash` CASE in upsertScannedFiles.
    func testUpsertClearsHashOnContentChange() throws {
        let queue = try migratedQueue()
        func upsert(size: Int, modified: String) throws {
            try queue.write { db in
                try db.execute(sql: """
                    INSERT INTO media_files(id,scan_root,file_path,file_name,file_type,file_size,file_modified_at,is_favorite,created_at,updated_at)
                    VALUES('id1','/r','/r/a.jpg','a.jpg','photo',?,?,0,'t','t')
                    ON CONFLICT(file_path) DO UPDATE SET
                      file_size=excluded.file_size, file_modified_at=excluded.file_modified_at,
                      content_hash = CASE
                        WHEN file_size IS NOT excluded.file_size OR file_modified_at IS NOT excluded.file_modified_at
                        THEN NULL ELSE content_hash END
                    """, arguments: [size, modified])
            }
        }
        try queue.write { db in try db.execute(sql: "INSERT INTO scan_roots(path,last_scanned_at,total_files) VALUES('/r','t',0)") }
        try upsert(size: 100, modified: "m1")
        try queue.write { db in try db.execute(sql: "UPDATE media_files SET content_hash='abc' WHERE id='id1'") }

        try upsert(size: 100, modified: "m1")   // unchanged → hash preserved
        XCTAssertEqual(try queue.read { try MediaFile.fetchOne($0, key: "id1")?.contentHash }, "abc")

        try upsert(size: 200, modified: "m1")   // size changed → hash cleared
        XCTAssertNil(try queue.read { try MediaFile.fetchOne($0, key: "id1")?.contentHash })
    }

    /// The hash-candidate query returns only files that share a byte-size (the size pre-filter);
    /// a uniquely-sized file is never hashed. Mirrors DatabaseService.pathsNeedingHash.
    func testPathsNeedingHashSizePreFilter() throws {
        let queue = try migratedQueue()
        try queue.write { db in
            try db.execute(sql: "INSERT INTO scan_roots(path,last_scanned_at,total_files) VALUES('/r','t',0)")
            for (id, path, size) in [("a", "/r/a", 100), ("b", "/r/b", 100), ("c", "/r/c", 200)] {
                try db.execute(sql: "INSERT INTO media_files(id,scan_root,file_path,file_name,file_type,file_size,is_favorite,created_at,updated_at) VALUES(?,'/r',?,?,'photo',?,0,'t','t')",
                               arguments: [id, path, path, size])
            }
        }
        let candidates = try queue.read { db in
            try String.fetchAll(db, sql: """
                SELECT file_path FROM media_files
                WHERE scan_root='/r' AND deleted_at IS NULL AND content_hash IS NULL AND file_size IS NOT NULL
                  AND file_size IN (SELECT file_size FROM media_files WHERE scan_root='/r' AND deleted_at IS NULL AND file_size IS NOT NULL GROUP BY file_size HAVING COUNT(*) > 1)
                ORDER BY file_path
                """)
        }
        XCTAssertEqual(candidates, ["/r/a", "/r/b"])   // the unique-size /r/c is excluded
    }

    /// A root keeps its section + position columns through a round-trip (migration v4).
    func testScanRootSectionColumnsRoundTrip() throws {
        let queue = try migratedQueue()
        try queue.write { db in
            try db.execute(sql: "INSERT INTO sidebar_sections(id,name,sort_order,created_at) VALUES('s1','Trips',0,'t')")
            try db.execute(sql: """
                INSERT INTO scan_roots(path,last_scanned_at,total_files,section_id,sort_order)
                VALUES('/r','t',0,'s1',3)
                """)
        }
        let root = try queue.read { db in try ScanRoot.fetchOne(db, key: "/r") }
        XCTAssertEqual(root?.sectionId, "s1")
        XCTAssertEqual(root?.sortOrder, 3)
    }

    /// Deleting a section falls its roots back to the default group (section_id ← NULL).
    func testDeleteSectionFallsRootsBackToDefault() throws {
        let queue = try migratedQueue()
        try queue.write { db in
            try db.execute(sql: "INSERT INTO sidebar_sections(id,name,sort_order,created_at) VALUES('s1','Trips',0,'t')")
            try db.execute(sql: "INSERT INTO scan_roots(path,last_scanned_at,total_files,section_id) VALUES('/r','t',0,'s1')")
            // Mirrors DatabaseService.deleteSection: reparent, then delete.
            try db.execute(sql: "UPDATE scan_roots SET section_id=NULL WHERE section_id='s1'")
            try db.execute(sql: "DELETE FROM sidebar_sections WHERE id='s1'")
        }
        try queue.read { db in
            XCTAssertNil(try ScanRoot.fetchOne(db, key: "/r")?.sectionId, "root should fall back to default group")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sidebar_sections"), 0)
        }
    }

    /// A reorder assigns sequential sort_order matching the new path order.
    func testReorderAssignsSequentialSortOrder() throws {
        let queue = try migratedQueue()
        try queue.write { db in
            for (i, p) in ["/a", "/b", "/c"].enumerated() {
                try db.execute(sql: "INSERT INTO scan_roots(path,last_scanned_at,total_files,sort_order) VALUES(?,?,0,?)",
                               arguments: [p, "t", i])
            }
            // Mirrors DatabaseService.reorderScanRoots for the new order c, a, b.
            for (i, p) in ["/c", "/a", "/b"].enumerated() {
                try db.execute(sql: "UPDATE scan_roots SET sort_order=? WHERE path=?", arguments: [i, p])
            }
        }
        let roots = try queue.read { db in try ScanRoot.order(Column("sort_order")).fetchAll(db) }
        XCTAssertEqual(roots.map(\.path), ["/c", "/a", "/b"])
        XCTAssertEqual(roots.map(\.sortOrder), [0, 1, 2])
    }

    func testHiddenColumnRoundTrips() throws {
        let queue = try migratedQueue()
        try queue.write { db in
            try db.execute(sql: "INSERT INTO scan_roots(path,last_scanned_at,total_files) VALUES('/r','t',0)")
            try db.execute(sql: """
                INSERT INTO media_files(id,scan_root,file_path,file_name,file_type,is_favorite,is_hidden,created_at,updated_at)
                VALUES('h1','/r','/r/a.jpg','a.jpg','photo',0,1,'t','t')
                """)
        }
        let f = try queue.read { db in try MediaFile.fetchOne(db, key: "h1") }
        XCTAssertEqual(f?.isHidden, true)
        XCTAssertEqual(f?.isFavorite, false)
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

    /// The shared upsert SQL used by the re-scan tests below — mirrors
    /// `DatabaseService.upsertScannedFiles` (incl. the `missing_at = NULL` reappear clear).
    private func upsert(_ db: Database, id: String, path: String, size: Int, at ts: String) throws {
        try db.execute(sql: """
            INSERT INTO media_files(id,scan_root,file_path,file_name,file_type,file_size,is_favorite,created_at,updated_at)
            VALUES(?, '/r', ?, 'a.jpg', 'photo', ?, 0, ?, ?)
            ON CONFLICT(file_path) DO UPDATE SET
              file_name=excluded.file_name, file_type=excluded.file_type,
              file_size=excluded.file_size, updated_at=excluded.updated_at, missing_at=NULL
            """, arguments: [id, path, size, ts, ts])
    }

    /// The missing-files watermark sweep — mirrors `DatabaseService.markMissingFiles`.
    private func sweepMissing(_ db: Database, now: String) throws {
        try db.execute(sql: """
            UPDATE media_files SET missing_at = ?, updated_at = ?
            WHERE scan_root = '/r' AND deleted_at IS NULL AND missing_at IS NULL AND updated_at < ?
            """, arguments: [now, now, now])
    }

    /// A re-scan that no longer finds a file flags it missing; files still present aren't touched.
    func testRescanMarksMissingFiles() throws {
        let queue = try migratedQueue()
        try queue.write { db in
            try db.execute(sql: "INSERT INTO scan_roots(path,last_scanned_at,total_files) VALUES('/r','t1',0)")
            try upsert(db, id: "a", path: "/r/a.jpg", size: 1, at: "t1")
            try upsert(db, id: "b", path: "/r/b.jpg", size: 1, at: "t1")
            // Re-scan at t2 finds only A; B is gone.
            try upsert(db, id: "a2", path: "/r/a.jpg", size: 2, at: "t2")
            try sweepMissing(db, now: "t2")
        }
        try queue.read { db in
            let a = try MediaFile.filter(Column("file_path") == "/r/a.jpg").fetchOne(db)
            let b = try MediaFile.filter(Column("file_path") == "/r/b.jpg").fetchOne(db)
            XCTAssertNil(a?.missingAt, "present file should not be marked missing")
            XCTAssertEqual(b?.missingAt, "t2", "absent file should be marked missing")
        }
    }

    /// A file that reappears in a later scan clears its missing flag (the ON CONFLICT clause).
    func testReappearedFileClearsMissing() throws {
        let queue = try migratedQueue()
        try queue.write { db in
            try db.execute(sql: "INSERT INTO scan_roots(path,last_scanned_at,total_files) VALUES('/r','t1',0)")
            try upsert(db, id: "b", path: "/r/b.jpg", size: 1, at: "t1")
            try sweepMissing(db, now: "t2")                 // B not seen at t2 → missing
            XCTAssertEqual(try MediaFile.filter(Column("file_path") == "/r/b.jpg").fetchOne(db)?.missingAt, "t2")
            try upsert(db, id: "b2", path: "/r/b.jpg", size: 9, at: "t3")  // B reappears
        }
        let b = try queue.read { db in try MediaFile.filter(Column("file_path") == "/r/b.jpg").fetchOne(db) }
        XCTAssertNil(b?.missingAt, "reappeared file should clear its missing flag")
        XCTAssertEqual(b?.fileSize, 9)
    }

    /// A user-deleted file (deleted_at set) is never reclassified as merely "missing".
    func testDeletedFileNotMarkedMissing() throws {
        let queue = try migratedQueue()
        try queue.write { db in
            try db.execute(sql: "INSERT INTO scan_roots(path,last_scanned_at,total_files) VALUES('/r','t1',0)")
            try upsert(db, id: "d", path: "/r/d.jpg", size: 1, at: "t1")
            try db.execute(sql: "UPDATE media_files SET deleted_at='t1' WHERE id='d'")
            try sweepMissing(db, now: "t2")
        }
        let d = try queue.read { db in try MediaFile.fetchOne(db, key: "d") }
        XCTAssertNil(d?.missingAt, "a deleted file stays deleted, not missing")
    }

    /// A drag-move across sections: set section_id, then renumber the target group — the moved
    /// root lands in the new section and the others keep their order. Mirrors AppState.moveRoot.
    func testDragMoveAcrossSections() throws {
        let queue = try migratedQueue()
        try queue.write { db in
            try db.execute(sql: "INSERT INTO sidebar_sections(id,name,sort_order,created_at) VALUES('s1','Trips',0,'t')")
            for (i, p) in ["/a", "/b", "/c"].enumerated() {
                try db.execute(sql: "INSERT INTO scan_roots(path,last_scanned_at,total_files,sort_order) VALUES(?,?,0,?)",
                               arguments: [p, "t", i])
            }
            // Move /b into section s1 (target group becomes just ["/b"] → sort_order 0).
            try db.execute(sql: "UPDATE scan_roots SET section_id='s1' WHERE path='/b'")
            try db.execute(sql: "UPDATE scan_roots SET sort_order=0 WHERE path='/b'")
        }
        try queue.read { db in
            let b = try ScanRoot.fetchOne(db, key: "/b")
            XCTAssertEqual(b?.sectionId, "s1")
            XCTAssertEqual(b?.sortOrder, 0)
            // The default group keeps /a then /c, in order.
            let defaults = try ScanRoot
                .filter(Column("section_id") == nil)
                .order(Column("sort_order"))
                .fetchAll(db)
                .map(\.path)
            XCTAssertEqual(defaults, ["/a", "/c"])
        }
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

    /// The pure folder behind `allFileKeywordNames`: groups name-sorted rows per file, keeps
    /// multi-tag order, and omits files that never appear (untagged files have no rows).
    func testGroupFileKeywordRows() {
        let rows: [(fileId: String, name: String)] = [
            ("m1", "Beach"), ("m1", "Sun"),   // multi-tag file, already name-sorted by the query
            ("m2", "Sun"),                     // single tag
        ]
        let map = DatabaseService.groupFileKeywordRows(rows)
        XCTAssertEqual(map["m1"], ["Beach", "Sun"])
        XCTAssertEqual(map["m2"], ["Sun"])
        XCTAssertNil(map["m3"], "untagged files must be absent from the map")
    }

    /// End-to-end: the real JOIN query feeding the real grouping helper returns each tagged
    /// file's sorted names and nothing for untagged files. This is what the grid's tag labels
    /// and "Tagged only" filter read.
    func testAllFileKeywordNamesQueryShape() throws {
        let queue = try migratedQueue()
        try queue.write { db in
            try db.execute(sql: "INSERT INTO scan_roots(path,last_scanned_at,total_files) VALUES('/r','t',0)")
            for id in ["m1", "m2", "m3"] {
                try db.execute(sql: """
                    INSERT INTO media_files(id,scan_root,file_path,file_name,file_type,is_favorite,created_at,updated_at)
                    VALUES(?, '/r', ?, ?, 'photo', 0, 't', 't')
                    """, arguments: [id, "/r/\(id).jpg", "\(id).jpg"])
            }
            try db.execute(sql: "INSERT INTO keywords(id,name,source,created_at) VALUES('k1','Sun','local','t')")
            try db.execute(sql: "INSERT INTO keywords(id,name,source,created_at) VALUES('k2','Beach','local','t')")
            // m1 has two tags, m2 has one, m3 has none.
            try db.execute(sql: "INSERT INTO file_keywords(file_id,keyword_id) VALUES('m1','k1')")
            try db.execute(sql: "INSERT INTO file_keywords(file_id,keyword_id) VALUES('m1','k2')")
            try db.execute(sql: "INSERT INTO file_keywords(file_id,keyword_id) VALUES('m2','k1')")
        }
        let map = try queue.read { db -> [String: [String]] in
            let rows = try Row.fetchAll(db, sql: """
                SELECT fk.file_id AS file_id, k.name AS name
                FROM file_keywords fk
                JOIN keywords k ON k.id = fk.keyword_id
                ORDER BY k.name
                """)
            return DatabaseService.groupFileKeywordRows(rows.map { ($0["file_id"], $0["name"]) })
        }
        XCTAssertEqual(map["m1"], ["Beach", "Sun"])   // ORDER BY k.name
        XCTAssertEqual(map["m2"], ["Sun"])
        XCTAssertNil(map["m3"])                        // untagged → absent
        XCTAssertEqual(map.count, 2)
    }
}
