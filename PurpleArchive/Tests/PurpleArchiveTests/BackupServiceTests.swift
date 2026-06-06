import XCTest
@testable import PurpleArchive

/// Mirrors the Timeliner backup test shape: zip round-trip, retention trims only
/// our prefixed archives, and listing is newest-first.
@MainActor
final class BackupServiceTests: XCTestCase {

    private var tmp: URL!
    private var fm: FileManager { .default }

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("pa-bk-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: tmp) }

    func testBackupRoundTrip() throws {
        let support = tmp.appendingPathComponent("support")
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        try "hello".write(to: support.appendingPathComponent("settings.json"),
                          atomically: true, encoding: .utf8)
        let backupDir = tmp.appendingPathComponent("backups")

        let url = try BackupService.runBackup(supportDir: support, backupDir: backupDir)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("PurpleArchive-"))
        XCTAssertTrue(url.pathExtension == "zip")
        XCTAssertTrue(fm.fileExists(atPath: url.path))
        XCTAssertGreaterThan((try fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0, 0)
    }

    func testRetentionTrimsOnlyOurArchivesAndOnlyOld() throws {
        let backupDir = tmp.appendingPathComponent("backups")
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        // An old "ours", a fresh "ours", and an unrelated file.
        let old = backupDir.appendingPathComponent("PurpleArchive-2000-01-01-000000.zip")
        let fresh = backupDir.appendingPathComponent("PurpleArchive-2099-01-01-000000.zip")
        let alien = backupDir.appendingPathComponent("not-ours.zip")
        for u in [old, fresh, alien] { try Data("x".utf8).write(to: u) }
        // Backdate the "old" one well past retention.
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: old.path)

        let removed = BackupService.trimOldBackups(in: backupDir, retentionDays: 14)
        XCTAssertEqual(removed, 1)
        XCTAssertFalse(fm.fileExists(atPath: old.path))
        XCTAssertTrue(fm.fileExists(atPath: fresh.path))
        XCTAssertTrue(fm.fileExists(atPath: alien.path), "must not touch non-PurpleArchive files")
    }

    func testListingNewestFirst() throws {
        let backupDir = tmp.appendingPathComponent("backups")
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let a = backupDir.appendingPathComponent("PurpleArchive-a.zip")
        let b = backupDir.appendingPathComponent("PurpleArchive-b.zip")
        try Data("a".utf8).write(to: a); try Data("b".utf8).write(to: b)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: a.path)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: b.path)
        let list = BackupService.listBackups(in: backupDir)
        XCTAssertEqual(list.first?.url.lastPathComponent, "PurpleArchive-b.zip")
        XCTAssertEqual(list.count, 2)
    }
}
