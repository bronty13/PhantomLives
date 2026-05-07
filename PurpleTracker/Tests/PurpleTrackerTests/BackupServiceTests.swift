import XCTest
@testable import PurpleTracker

final class BackupServiceTests: XCTestCase {

    private func makeSourceDir() throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("pt-bkp-src-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "fake-sqlite".data(using: .utf8)!.write(to: dir.appendingPathComponent("purpletracker.sqlite"))
        try "{}".data(using: .utf8)!.write(to: dir.appendingPathComponent("settings.json"))
        return dir
    }

    private func makeBackupDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pt-bkp-dst-\(UUID().uuidString)", isDirectory: true)
    }

    @MainActor
    func testRunBackupAutoCreatesTargetDirectory() throws {
        let src = try makeSourceDir()
        let dst = makeBackupDir()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst.path))

        let url = try BackupService.runBackup(supportDir: src, backupDir: dst)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(url.lastPathComponent.hasPrefix(BackupService.archivePrefix))
        XCTAssertEqual(url.pathExtension, "zip")
    }

    @MainActor
    func testTrimRemovesOnlyOldArchives() throws {
        let dst = makeBackupDir()
        let fm = FileManager.default
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        let fresh = dst.appendingPathComponent("\(BackupService.archivePrefix)2026-05-01-000000.zip")
        let stale = dst.appendingPathComponent("\(BackupService.archivePrefix)2025-05-01-000000.zip")
        try Data([0x50,0x4B,0x05,0x06]).write(to: fresh)
        try Data([0x50,0x4B,0x05,0x06]).write(to: stale)

        let oldDate = Date().addingTimeInterval(-60 * 86400)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: stale.path)

        let unrelated = dst.appendingPathComponent("notes.txt")
        try "hi".data(using: .utf8)!.write(to: unrelated)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: unrelated.path)

        let removed = BackupService.trimOldBackups(in: dst, retentionDays: 30)
        XCTAssertEqual(removed, 1)
        XCTAssertFalse(fm.fileExists(atPath: stale.path))
        XCTAssertTrue(fm.fileExists(atPath: fresh.path))
        XCTAssertTrue(fm.fileExists(atPath: unrelated.path))
    }

    @MainActor
    func testRetentionZeroKeepsEverything() throws {
        let dst = makeBackupDir()
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        let archive = dst.appendingPathComponent("\(BackupService.archivePrefix)2024-01-01-000000.zip")
        try Data([0x50,0x4B,0x05,0x06]).write(to: archive)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-365 * 86400)],
            ofItemAtPath: archive.path
        )
        XCTAssertEqual(BackupService.trimOldBackups(in: dst, retentionDays: 0), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
    }

    @MainActor
    func testListBackupsSortedNewestFirst() throws {
        let dst = makeBackupDir()
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
        XCTAssertEqual(list.first?.url.lastPathComponent, b.lastPathComponent)
    }
}
