import XCTest
@testable import PurpleDedupCore

final class BackupServiceTests: XCTestCase {

    func testBackupProducesNonEmptyArchive() throws {
        let support = try TestFixtures.makeTempDir("bkp-support")
        let backup = try TestFixtures.makeTempDir("bkp-out")
        defer {
            TestFixtures.cleanup(support)
            TestFixtures.cleanup(backup)
        }

        try TestFixtures.write("payload", to: support.appendingPathComponent("data.json"))
        try TestFixtures.write(Data([0xCA, 0xFE]), to: support.appendingPathComponent("blob.bin"))

        let archive = try BackupService.runBackup(supportDir: support, backupDir: backup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        XCTAssertTrue(archive.lastPathComponent.hasPrefix(BackupService.archivePrefix))
        let size = (try archive.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        XCTAssertGreaterThan(size, 0)
    }

    func testTrimRespectsRetentionAndPrefix() throws {
        let backup = try TestFixtures.makeTempDir("bkp-trim")
        defer { TestFixtures.cleanup(backup) }

        let old = backup.appendingPathComponent("\(BackupService.archivePrefix)old.zip")
        let recent = backup.appendingPathComponent("\(BackupService.archivePrefix)new.zip")
        let unrelated = backup.appendingPathComponent("vacation-photos.zip")

        try Data([0]).write(to: old)
        try Data([0]).write(to: recent)
        try Data([0]).write(to: unrelated)

        let veryOld = Date().addingTimeInterval(-30 * 86400)
        try FileManager.default.setAttributes([.modificationDate: veryOld], ofItemAtPath: old.path)

        let removed = BackupService.trimOldBackups(in: backup, retentionDays: 14)
        XCTAssertEqual(removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path),
            "Recent prefixed archive must survive")
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path),
            "Unrelated zip must NOT be touched (retention scopes by prefix)")
    }

    func testListBackupsNewestFirst() throws {
        let backup = try TestFixtures.makeTempDir("bkp-list")
        defer { TestFixtures.cleanup(backup) }

        let a = backup.appendingPathComponent("\(BackupService.archivePrefix)a.zip")
        let b = backup.appendingPathComponent("\(BackupService.archivePrefix)b.zip")
        try Data([0]).write(to: a)
        try Data([0]).write(to: b)

        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-3600)],
            ofItemAtPath: a.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: b.path
        )

        let entries = BackupService.listBackups(in: backup)
        XCTAssertEqual(entries.map { $0.url.lastPathComponent }, [b.lastPathComponent, a.lastPathComponent])
    }
}
