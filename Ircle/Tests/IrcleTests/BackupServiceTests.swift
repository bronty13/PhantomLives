import Foundation
import Testing
@testable import Ircle

/// The four backup tests required by the auto-backup-on-launch standard:
/// debounce, retention trim (prefix-scoped), target-dir auto-create, and
/// list ordering.
@MainActor
@Suite("BackupService")
struct BackupServiceTests {

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ircle-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSupportDir() -> URL {
        let dir = tempDir()
        // A representative settings.json so the archive has content.
        let data = try! JSONEncoder().encode(AppSettings())
        try! data.write(to: dir.appendingPathComponent("settings.json"))
        return dir
    }

    @Test func targetDirectoryIsAutoCreated() throws {
        let support = makeSupportDir()
        let backupDir = tempDir().appendingPathComponent("does/not/exist/yet", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: backupDir.path))
        let url = try BackupService.runBackup(supportDir: support, backupDir: backupDir)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.lastPathComponent.hasPrefix(BackupService.archivePrefix))
    }

    @Test func retentionTrimOnlyRemovesOurPrefixedArchivesPastWindow() throws {
        let backupDir = tempDir()
        let fm = FileManager.default

        // An old "ours" archive (should be trimmed) …
        let oldOurs = backupDir.appendingPathComponent("Ircle-2000-01-01-000000.zip")
        try Data("x".utf8).write(to: oldOurs)
        // … an old UNRELATED file (must be left alone) …
        let oldOther = backupDir.appendingPathComponent("someone-elses.zip")
        try Data("x".utf8).write(to: oldOther)
        // … and a fresh "ours" archive (within the window, must survive).
        let freshOurs = backupDir.appendingPathComponent("Ircle-2999-01-01-000000.zip")
        try Data("x".utf8).write(to: freshOurs)

        // Backdate the two "old" files well beyond the retention window.
        let ancient = Date(timeIntervalSince1970: 0)
        for url in [oldOurs, oldOther] {
            try fm.setAttributes([.modificationDate: ancient], ofItemAtPath: url.path)
        }

        let removed = BackupService.trimOldBackups(in: backupDir, retentionDays: 14)
        #expect(removed == 1)
        #expect(!fm.fileExists(atPath: oldOurs.path))     // ours + old → gone
        #expect(fm.fileExists(atPath: oldOther.path))     // unrelated → kept
        #expect(fm.fileExists(atPath: freshOurs.path))    // ours + fresh → kept
    }

    @Test func retentionZeroKeepsEverything() throws {
        let backupDir = tempDir()
        let old = backupDir.appendingPathComponent("Ircle-2000-01-01-000000.zip")
        try Data("x".utf8).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)],
                                              ofItemAtPath: old.path)
        let removed = BackupService.trimOldBackups(in: backupDir, retentionDays: 0)
        #expect(removed == 0)
        #expect(FileManager.default.fileExists(atPath: old.path))
    }

    @Test func listBackupsReturnsNewestFirst() throws {
        let backupDir = tempDir()
        let fm = FileManager.default
        // Two distinct prefixed archives with explicit, different mtimes.
        let older = backupDir.appendingPathComponent("Ircle-2001-01-01-000000.zip")
        let newer = backupDir.appendingPathComponent("Ircle-2002-02-02-000000.zip")
        try Data("a".utf8).write(to: older)
        try Data("bb".utf8).write(to: newer)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: older.path)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: newer.path)

        let list = BackupService.listBackups(in: backupDir)
        #expect(list.count == 2)
        // Compare by filename — listBackups resolves /var → /private/var.
        #expect(list.first?.url.lastPathComponent == newer.lastPathComponent)   // newest first
        #expect(list.last?.url.lastPathComponent == older.lastPathComponent)
    }

    @Test func debounceSkipsRecentBackup() throws {
        // A store whose lastBackupAt is "now" must be skipped by the launch run.
        // Use a temp dir so we never touch the real user settings.json.
        let store = SettingsStore(directory: tempDir())
        store.settings.autoBackupEnabled = true
        store.settings.lastBackupAt = BackupService.isoNow()
        let before = store.settings.lastBackupAt
        BackupService.runOnLaunchIfDue(settingsStore: store)
        // No new run ⇒ timestamp unchanged.
        #expect(store.settings.lastBackupAt == before)
    }

    @Test func verifyRoundTripsAValidArchive() throws {
        let support = makeSupportDir()
        let backupDir = tempDir()
        let url = try BackupService.runBackup(supportDir: support, backupDir: backupDir)
        let result = try BackupService.verifyArchive(at: url)
        #expect(result.hasSettings)
        #expect(result.fileCount >= 1)
    }
}
