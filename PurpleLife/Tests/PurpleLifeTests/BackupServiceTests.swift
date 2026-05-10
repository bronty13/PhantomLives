import XCTest
@testable import PurpleLife

/// The four required backup tests called out in PLAN.md § PhantomLives
/// conventions checklist. Mirror Timeliner's BackupServiceTests so the
/// pattern stays uniform across the family.
final class BackupServiceTests: XCTestCase {

    // MARK: - Helpers

    /// Synthetic source directory with a few files in it. Stands in for the
    /// real `~/Library/Application Support/PurpleLife/`.
    private func makeSourceDir(extraFiles: Int = 2) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appendingPathComponent("pl-bkp-src-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "fake-sqlite".data(using: .utf8)!.write(to: dir.appendingPathComponent("purplelife.sqlite"))
        try "{}".data(using: .utf8)!.write(to: dir.appendingPathComponent("settings.json"))
        for i in 0..<extraFiles {
            try "file \(i)".data(using: .utf8)!
                .write(to: dir.appendingPathComponent("extra-\(i).txt"))
        }
        return dir
    }

    /// Empty (and not-yet-existing) directory the backup will write into.
    private func makeBackupDir() throws -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pl-bkp-dst-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - Required tests

    /// `target-directory auto-create` — runBackup succeeds even when the
    /// destination directory doesn't exist yet.
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

    /// `retention trim` — only files matching the `PurpleLife-` prefix in
    /// the backup dir are removed when older than the retention window;
    /// unrelated files are left alone.
    @MainActor
    func testTrimRemovesOnlyOldArchives() throws {
        let dst = try makeBackupDir()
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        let fm = FileManager.default

        // Two of our archives — one fresh, one ancient.
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

        // A foreign-app archive (different prefix) — also must not be touched.
        let foreign = dst.appendingPathComponent("Timeliner-2025-05-01-000000.zip")
        try Data([0x50,0x4B,0x05,0x06]).write(to: foreign)
        try fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: foreign.path)

        let removed = BackupService.trimOldBackups(in: dst, retentionDays: 14)
        XCTAssertEqual(removed, 1, "Exactly one stale PurpleLife archive should be removed")
        XCTAssertFalse(fm.fileExists(atPath: stale.path))
        XCTAssertTrue(fm.fileExists(atPath: fresh.path))
        XCTAssertTrue(fm.fileExists(atPath: unrelated.path),
                      "Non-archive files must be left alone")
        XCTAssertTrue(fm.fileExists(atPath: foreign.path),
                      "Sibling-app archives must be left alone")
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

    /// `list ordering` — listBackups returns newest-first.
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

    /// `debounce` — second call within 5 minutes is a no-op.
    @MainActor
    func testRunOnLaunchDebouncesWithinFiveMinutes() throws {
        let store = SettingsStore()
        // Drive the store with isolated paths so this test never touches
        // a developer's real ~/Downloads/PurpleLife backup/ directory.
        let dst = try makeBackupDir()
        var s = store.settings
        s.autoBackupEnabled = true
        s.backupPath = dst.path
        // Simulate a successful backup 10 seconds ago. ISO-8601 in the
        // local en_US_POSIX format the service uses.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        s.lastBackupAt = f.string(from: Date().addingTimeInterval(-10))
        store.settings = s

        let priorContents = (try? FileManager.default.contentsOfDirectory(at: dst, includingPropertiesForKeys: nil)) ?? []
        BackupService.runOnLaunchIfDue(settingsStore: store)
        let afterContents = (try? FileManager.default.contentsOfDirectory(at: dst, includingPropertiesForKeys: nil)) ?? []

        XCTAssertEqual(
            afterContents.count, priorContents.count,
            "Backup should not have run within the debounce window"
        )
    }
}
