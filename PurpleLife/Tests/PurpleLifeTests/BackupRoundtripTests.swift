import XCTest
import GRDB
@testable import PurpleLife

/// Phase 1 acceptance gate (PLAN.md § Phase acceptance tests, row 1):
///   "Create 100 random objects → force-quit → restart, all present.
///    Backup written to ~/Downloads/PurpleLife backup/, archive opens,
///    restore into a fresh support dir matches row counts."
///
/// We model the round-trip end-to-end against an isolated support
/// directory — no developer's real PurpleLife state is touched.
final class BackupRoundtripTests: XCTestCase {

    private func makeIsolatedSupportDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pl-roundtrip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func openPool(_ supportDir: URL) throws -> DatabasePool {
        let dbURL = supportDir.appendingPathComponent("purplelife.sqlite")
        let pool = try DatabasePool(path: dbURL.path)
        try DatabaseService.applyMigrations(to: pool)
        return pool
    }

    @MainActor
    func testRoundtrip100Objects() throws {
        // 1. Stand up a fresh support dir + DB pool, write 100 objects.
        let supportDir = try makeIsolatedSupportDir()
        let dbPool = try openPool(supportDir)
        var seeded: [String] = []
        try dbPool.write { db in
            let now = ISO8601DateFormatter().string(from: Date())
            for i in 0..<100 {
                let r = ObjectRecord(
                    id: UUID().uuidString,
                    typeId: ["Person", "Camera", "Book"].randomElement()!,
                    parentId: nil,
                    fieldsJSON: "{\"i\":\(i)}",
                    createdAt: now,
                    updatedAt: now
                )
                try r.insert(db)
                seeded.append(r.id)
            }
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM objects") ?? 0
            XCTAssertEqual(count, 100)
        }

        // 2. Drop the pool reference (simulates close) and run a backup.
        let backupDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pl-roundtrip-bkp-\(UUID().uuidString)", isDirectory: true)
        let archiveURL = try BackupService.runBackup(supportDir: supportDir, backupDir: backupDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))

        // 3. Verify the archive without restoring — counts match.
        let verify = try BackupService.verifyArchive(at: archiveURL)
        XCTAssertEqual(verify.objectCount, 100, "verifyArchive must report 100 objects")
        XCTAssertTrue(
            verify.entries.contains { $0.hasSuffix("purplelife.sqlite") },
            "Archive should contain purplelife.sqlite — entries: \(verify.entries)"
        )

        // 4. Wipe the original support dir — simulates "fresh machine" — and
        //    restore from the archive into it.
        if let contents = try? FileManager.default.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil) {
            for url in contents {
                try? FileManager.default.removeItem(at: url)
            }
        }
        XCTAssertEqual(
            (try? FileManager.default.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil))?.count,
            0,
            "Support dir should be empty before restore"
        )

        try BackupService.restoreArchive(at: archiveURL, into: supportDir)

        // 5. Reopen the restored DB and verify all 100 ids are still there.
        let restoredPool = try openPool(supportDir)
        let restoredIds = try restoredPool.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM objects ORDER BY id")
        }
        XCTAssertEqual(restoredIds.count, 100)
        XCTAssertEqual(Set(restoredIds), Set(seeded), "Every seeded id should survive restore")

        // Cleanup
        try? FileManager.default.removeItem(at: supportDir)
        try? FileManager.default.removeItem(at: backupDir)
    }
}
