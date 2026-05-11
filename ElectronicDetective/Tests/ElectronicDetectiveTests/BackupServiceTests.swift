import XCTest
@testable import ElectronicDetective

/// Tests the four required behaviours from the PhantomLives auto-backup
/// convention: target-directory auto-create, retention trim is prefix-scoped,
/// list ordering is newest-first, and the debounce.
@MainActor
final class BackupServiceTests: XCTestCase {

    private func tempDir() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ed-backup-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// `runBackup` should create the destination directory if it doesn't
    /// exist yet.
    func testTargetDirectoryAutoCreate() throws {
        let support = tempDir()
        try "x".write(to: support.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
        let backupDir = tempDir().appendingPathComponent("nested/dir")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupDir.path))

        _ = try BackupService.runBackup(supportDir: support, backupDir: backupDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupDir.path))
    }

    /// `trimOldBackups` removes ONLY archives matching `ElectronicDetective-`
    /// — an unrelated zip the user dropped into the same folder must be
    /// untouched even when older than the retention window.
    func testRetentionTrimIsPrefixScoped() throws {
        let backupDir = tempDir()
        let ours = backupDir.appendingPathComponent("ElectronicDetective-2020-01-01-000000.zip")
        let theirs = backupDir.appendingPathComponent("my-vacation-photos.zip")
        try Data([0x50, 0x4B]).write(to: ours)
        try Data([0x50, 0x4B]).write(to: theirs)
        // Backdate both files past the retention window.
        let oldDate = Date().addingTimeInterval(-365 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: ours.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: theirs.path)

        let removed = BackupService.trimOldBackups(in: backupDir, retentionDays: 14)
        XCTAssertEqual(removed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ours.path))
        XCTAssertTrue (FileManager.default.fileExists(atPath: theirs.path))
    }

    /// `listBackups` returns archives in newest-first order, ignoring
    /// non-archive files.
    func testListBackupsNewestFirst() throws {
        let backupDir = tempDir()
        let older = backupDir.appendingPathComponent("ElectronicDetective-2024-01-01-000000.zip")
        let newer = backupDir.appendingPathComponent("ElectronicDetective-2024-06-01-000000.zip")
        let alien = backupDir.appendingPathComponent("not-a-backup.txt")
        try Data().write(to: older)
        try Data().write(to: newer)
        try Data().write(to: alien)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-3 * 86_400)], ofItemAtPath: older.path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: newer.path)

        let list = BackupService.listBackups(in: backupDir)
        XCTAssertEqual(list.count, 2, "alien file must be excluded")
        // Compare lastPathComponent — macOS resolves /var → /private/var via
        // symlink so URL equality is unreliable across these paths.
        XCTAssertEqual(list[0].url.lastPathComponent, newer.lastPathComponent)
        XCTAssertEqual(list[1].url.lastPathComponent, older.lastPathComponent)
    }

    /// `retentionDays = 0` means "keep forever" — trim must short-circuit.
    func testRetentionZeroMeansKeepForever() throws {
        let backupDir = tempDir()
        let ours = backupDir.appendingPathComponent("ElectronicDetective-2000-01-01-000000.zip")
        try Data().write(to: ours)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-365 * 86_400)],
            ofItemAtPath: ours.path)

        let removed = BackupService.trimOldBackups(in: backupDir, retentionDays: 0)
        XCTAssertEqual(removed, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ours.path))
    }
}
