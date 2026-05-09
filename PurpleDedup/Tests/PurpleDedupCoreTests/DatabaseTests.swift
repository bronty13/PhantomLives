import XCTest
@testable import PurpleDedupCore

final class DatabaseTests: XCTestCase {

    func testMigratesFreshSchema() throws {
        let db = try Database.inMemory()
        XCTAssertEqual(try db.fileCount(), 0)
    }

    func testUpsertAddsAndUpdatesRows() throws {
        let db = try Database.inMemory()

        try db.upsertScanned(
            path: "/tmp/a.jpg",
            sizeBytes: 100,
            mtimeUnix: 1_700_000_000,
            fileType: "photo",
            format: "jpg",
            contentHash: nil
        )
        XCTAssertEqual(try db.fileCount(), 1)

        // Same path, updated mtime → in place; row count stays at 1.
        try db.upsertScanned(
            path: "/tmp/a.jpg",
            sizeBytes: 100,
            mtimeUnix: 1_700_001_000,
            fileType: "photo",
            format: "jpg",
            contentHash: Data([0xDE, 0xAD])
        )
        XCTAssertEqual(try db.fileCount(), 1)

        try db.upsertScanned(
            path: "/tmp/b.jpg",
            sizeBytes: 200,
            mtimeUnix: 1_700_002_000,
            fileType: "photo",
            format: "jpg",
            contentHash: nil
        )
        XCTAssertEqual(try db.fileCount(), 2)
    }

    func testRecordOperationAppends() throws {
        let db = try Database.inMemory()
        try db.recordOperation(
            operation: "trash",
            sourcePath: "/tmp/old.jpg",
            destinationPath: nil,
            fileSizeBytes: 1234,
            contentHash: nil
        )
        // No public read API yet (it lands when "Restore from log" ships in Phase 5),
        // but the insert succeeding is enough proof for now that the table + insert
        // path are wired.
        XCTAssertEqual(try db.fileCount(), 0)
    }

    func testV2MigrationCreatesFingerprintsTable() throws {
        // The migrator runs both v1 and v2 on a fresh in-memory DB. Verify the
        // fingerprints table exists by writing through the GRDB record.
        let db = try Database.inMemory()
        try db.writer.write { writer in
            // First need a parent row in `files` because of the FK.
            try writer.execute(
                sql: """
                INSERT INTO files (path, sizeBytes, mtimeUnix, fileType, format, lastIndexedUnix)
                VALUES ('/tmp/x.jpg', 100, 1700000000, 'photo', 'jpg', 1700000000)
                """
            )
            let id = writer.lastInsertedRowID
            var fp = FingerprintRecord(
                fileId: id,
                phash: UInt64(0xDEADBEEFCAFEBABE).littleEndianHashData,
                dhash: UInt64(0).littleEndianHashData,
                width: 1920,
                height: 1080,
                videoFingerprint: nil
            )
            try fp.insert(writer)
        }
        let n = try db.writer.read { reader in
            try Int.fetchOne(reader, sql: "SELECT COUNT(*) FROM fingerprints") ?? 0
        }
        XCTAssertEqual(n, 1)
    }

    func testHashEncodingRoundTrip() {
        let original: UInt64 = 0xDEADBEEF12345678
        let data = original.littleEndianHashData
        XCTAssertEqual(data.count, 8)
        let restored = UInt64(littleEndianHashData: data)
        XCTAssertEqual(original, restored)
    }
}
