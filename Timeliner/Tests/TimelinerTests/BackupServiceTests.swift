import XCTest
@testable import Timeliner

final class BackupServiceTests: XCTestCase {

    /// Helper — produce a synthetic source directory with a few files in it.
    private func makeSourceDir(extraFiles: Int = 2) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("tl-bkp-src-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "fake-sqlite".data(using: .utf8)!.write(to: dir.appendingPathComponent("timeliner.sqlite"))
        try "{}".data(using: .utf8)!.write(to: dir.appendingPathComponent("settings.json"))
        for i in 0..<extraFiles {
            try "file \(i)".data(using: .utf8)!.write(to: dir.appendingPathComponent("extra-\(i).txt"))
        }
        return dir
    }

    /// Helper — empty directory the backup will write into.
    private func makeBackupDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tl-bkp-dst-\(UUID().uuidString)", isDirectory: true)
        return dir
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

        // Two archives — one fresh, one ancient (modify timestamp 30 days ago).
        let fresh = dst.appendingPathComponent("\(BackupService.archivePrefix)2026-05-01-000000.zip")
        let stale = dst.appendingPathComponent("\(BackupService.archivePrefix)2025-05-01-000000.zip")
        try Data([0x50,0x4B,0x05,0x06]).write(to: fresh)
        try Data([0x50,0x4B,0x05,0x06]).write(to: stale)

        let oldDate = Date().addingTimeInterval(-30 * 86400)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: stale.path)

        // A non-archive file in the same directory must NOT be touched.
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
        // Compare last path components — macOS exposes /var/folders/... as
        // /private/var/folders/... when reading directory contents, so a
        // strict URL equality check is brittle.
        XCTAssertEqual(list.first?.url.lastPathComponent, b.lastPathComponent,
                       "Newest backup should be first")
    }
}
