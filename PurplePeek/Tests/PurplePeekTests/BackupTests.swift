import XCTest
@testable import PurplePeek

@MainActor
final class BackupTests: XCTestCase {

    private var support: URL!
    private var backupDir: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("pp-backup-\(UUID().uuidString)")
        support = base.appendingPathComponent("support", isDirectory: true)
        backupDir = base.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data("db".utf8).write(to: support.appendingPathComponent("purplepeek.sqlite"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: support.deletingLastPathComponent())
    }

    func testRunBackupCreatesNonEmptyPrefixedZip() throws {
        let url = try BackupService.runBackup(supportDir: support, backupDir: backupDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(url.lastPathComponent.hasPrefix(BackupService.archivePrefix))
        XCTAssertEqual(url.pathExtension, "zip")
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 0)
    }

    func testTrimRemovesOnlyOldPrefixedArchives() throws {
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let fm = FileManager.default
        func make(_ name: String, daysOld: Int) throws {
            let u = backupDir.appendingPathComponent(name)
            try Data("z".utf8).write(to: u)
            let date = Date().addingTimeInterval(-Double(daysOld) * 86400)
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: u.path)
        }
        try make("\(BackupService.archivePrefix)old.zip", daysOld: 30)
        try make("\(BackupService.archivePrefix)new.zip", daysOld: 1)
        try make("unrelated.zip", daysOld: 30)            // not ours — must survive

        let removed = BackupService.trimOldBackups(in: backupDir, retentionDays: 14)
        XCTAssertEqual(removed, 1)
        let remaining = Set(try fm.contentsOfDirectory(atPath: backupDir.path))
        XCTAssertTrue(remaining.contains("\(BackupService.archivePrefix)new.zip"))
        XCTAssertTrue(remaining.contains("unrelated.zip"))
        XCTAssertFalse(remaining.contains("\(BackupService.archivePrefix)old.zip"))
    }

    func testListBackupsNewestFirst() throws {
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let fm = FileManager.default
        func make(_ name: String, daysOld: Int) throws {
            let u = backupDir.appendingPathComponent(name)
            try Data("z".utf8).write(to: u)
            try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-Double(daysOld) * 86400)],
                                 ofItemAtPath: u.path)
        }
        try make("\(BackupService.archivePrefix)a.zip", daysOld: 3)
        try make("\(BackupService.archivePrefix)b.zip", daysOld: 1)
        let list = BackupService.listBackups(in: backupDir)
        XCTAssertEqual(list.map { $0.url.lastPathComponent },
                       ["\(BackupService.archivePrefix)b.zip", "\(BackupService.archivePrefix)a.zip"])
    }

    func testRetentionZeroKeepsEverything() throws {
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let u = backupDir.appendingPathComponent("\(BackupService.archivePrefix)x.zip")
        try Data("z".utf8).write(to: u)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-9999 * 86400)],
                                              ofItemAtPath: u.path)
        XCTAssertEqual(BackupService.trimOldBackups(in: backupDir, retentionDays: 0), 0)
    }
}
