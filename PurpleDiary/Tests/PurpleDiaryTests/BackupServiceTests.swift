import XCTest
import GRDB
@testable import PurpleDiary

final class BackupServiceTests: XCTestCase {

    private func makeSourceDir(extraFiles: Int = 2) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("pd-bkp-src-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "fake-sqlite".data(using: .utf8)!.write(to: dir.appendingPathComponent("diary.sqlite"))
        try "{}".data(using: .utf8)!.write(to: dir.appendingPathComponent("settings.json"))
        for i in 0..<extraFiles {
            try "file \(i)".data(using: .utf8)!.write(to: dir.appendingPathComponent("extra-\(i).txt"))
        }
        return dir
    }

    private func makeBackupDir() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pd-bkp-dst-\(UUID().uuidString)", isDirectory: true)
    }

    @MainActor
    func testRunBackupAutoCreatesTargetDirectory() throws {
        let src = try makeSourceDir()
        let dst = try makeBackupDir()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst.path))

        let url = try BackupService.runBackup(supportDir: src, backupDir: dst)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(url.lastPathComponent.hasPrefix(BackupService.archivePrefix))
        XCTAssertEqual(url.pathExtension, "zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.path),
                      "Backup directory should be created on demand")
    }

    @MainActor
    func testTrimRemovesOnlyOldArchives() throws {
        let dst = try makeBackupDir()
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        let fm = FileManager.default

        let fresh = dst.appendingPathComponent("\(BackupService.archivePrefix)2026-05-01-000000.zip")
        let stale = dst.appendingPathComponent("\(BackupService.archivePrefix)2025-05-01-000000.zip")
        try Data([0x50,0x4B,0x05,0x06]).write(to: fresh)
        try Data([0x50,0x4B,0x05,0x06]).write(to: stale)

        let oldDate = Date().addingTimeInterval(-30 * 86400)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: stale.path)

        let unrelated = dst.appendingPathComponent("notes.txt")
        try "hi".data(using: .utf8)!.write(to: unrelated)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: unrelated.path)

        let removed = BackupService.trimOldBackups(in: dst, retentionDays: 14)
        XCTAssertEqual(removed, 1, "One stale archive should be removed")
        XCTAssertFalse(fm.fileExists(atPath: stale.path))
        XCTAssertTrue(fm.fileExists(atPath: fresh.path))
        XCTAssertTrue(fm.fileExists(atPath: unrelated.path),
                      "Non-archive files must be left alone")
    }

    @MainActor
    func testTrimWithRetentionZeroKeepsEverything() throws {
        let dst = try makeBackupDir()
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        let archive = dst.appendingPathComponent("\(BackupService.archivePrefix)2024-01-01-000000.zip")
        try Data([0x50,0x4B,0x05,0x06]).write(to: archive)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-365 * 86400)],
            ofItemAtPath: archive.path
        )
        let removed = BackupService.trimOldBackups(in: dst, retentionDays: 0)
        XCTAssertEqual(removed, 0, "retentionDays=0 means keep forever")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
    }

    @MainActor
    func testListBackupsSortedNewestFirst() throws {
        let dst = try makeBackupDir()
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        let a = dst.appendingPathComponent("\(BackupService.archivePrefix)A.zip")
        let b = dst.appendingPathComponent("\(BackupService.archivePrefix)B.zip")
        try Data([0]).write(to: a)
        try Data([0]).write(to: b)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-3600)],
            ofItemAtPath: a.path
        )
        let list = BackupService.listBackups(in: dst)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list.first?.url.lastPathComponent, b.lastPathComponent,
                       "Newest backup should be first")
    }

    /// Backup → verify round-trip on a real (tiny) GRDB database so the verify
    /// path's row counting is exercised end to end.
    @MainActor
    func testBackupThenVerifyReportsEntryCount() throws {
        let fm = FileManager.default
        let src = fm.temporaryDirectory.appendingPathComponent("pd-verify-src-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: src) }

        // Build a real diary.sqlite with two entries.
        let dbURL = src.appendingPathComponent("diary.sqlite")
        let pool = try DatabasePool(path: dbURL.path)
        try DatabaseService.applyMigrations(to: pool)
        try pool.write { db in
            var e1 = Entry.newDraft(title: "one"); e1.id = "1"; try e1.insert(db)
            var e2 = Entry.newDraft(title: "two"); e2.id = "2"; try e2.insert(db)
        }

        let dst = try makeBackupDir()
        let archive = try BackupService.runBackup(supportDir: src, backupDir: dst)
        let result = try BackupService.verifyArchive(at: archive)
        XCTAssertEqual(result.entryCount, 2)
        XCTAssertTrue(result.migrations.contains("v1_initial"))
    }
}
