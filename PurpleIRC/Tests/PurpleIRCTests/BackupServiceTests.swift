import Foundation
import CryptoKit
import Testing
@testable import PurpleIRC

/// End-to-end round-trip coverage for BackupService — the only safety
/// net the app has against another settings-clobber incident. Each
/// test plants a known support-directory layout, runs a backup, optionally
/// wipes the support dir, and either verifies or restores the archive.
/// The support-dir name MUST end in `PurpleIRC` because both
/// `FactoryReset.wipe` and `BackupService.restore` refuse to operate
/// on non-PurpleIRC directories — the safety guard the production code
/// uses to prevent an accidental support-pointer redirect from wiping
/// `~/Library`.
@Suite("BackupService")
struct BackupServiceTests {

    // MARK: - Fixtures

    private func tempPair() -> (support: URL, backup: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupServiceTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try? FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true)
        // Final component MUST be `PurpleIRC` — the wipe / restore
        // safety guard hard-checks for it.
        let support = root.appendingPathComponent("PurpleIRC", isDirectory: true)
        let backup = root.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        return (support, backup)
    }

    /// Plant a few representative files under `support` so the archive
    /// has identifiable contents for the assertion phase.
    private func plant(in support: URL) throws {
        let fm = FileManager.default
        try Data("settings".utf8).write(
            to: support.appendingPathComponent("settings.json"))
        try Data("keystore".utf8).write(
            to: support.appendingPathComponent("keystore.json"))
        let logsDir = support.appendingPathComponent("logs/abc/", isDirectory: true)
        try fm.createDirectory(at: logsDir, withIntermediateDirectories: true)
        try Data("log line\nanother line\n".utf8).write(
            to: logsDir.appendingPathComponent("buffer.log"))
        let dlDir = support.appendingPathComponent("downloads", isDirectory: true)
        try fm.createDirectory(at: dlDir, withIntermediateDirectories: true)
        try Data("(should be excluded from backup)".utf8).write(
            to: dlDir.appendingPathComponent("BIG_FILE.bin"))
    }

    // MARK: - Plain (no-key) round-trip

    @Test func plainBackupAndRestoreRoundtrip() throws {
        let (support, backup) = tempPair()
        try plant(in: support)

        // 1. Run backup with no key — produces a plain .zip.
        let archive = try BackupService.runBackup(
            supportDir: support, backupDir: backup, key: nil)
        #expect(archive.pathExtension == "zip")
        #expect(FileManager.default.fileExists(atPath: archive.path))

        // 2. Verify works.
        let v = try BackupService.verifyArchive(at: archive, key: nil)
        #expect(v.fileCount >= 3)                // settings + keystore + log
        #expect(v.isEncryptedArchive == false)
        // Make sure downloads/ was excluded — this protects users with
        // multi-GB DCC archives from waking up to GB-sized backup files.
        #expect(!v.sampleEntries.contains(where: { $0.contains("downloads/") }))

        // 3. Wipe the support dir and restore.
        for entry in try FileManager.default.contentsOfDirectory(
            at: support, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: entry)
        }
        try BackupService.restore(from: archive, into: support, key: nil)

        // 4. Restored content matches what we planted.
        let settingsBytes = try? Data(contentsOf: support.appendingPathComponent("settings.json"))
        #expect(String(data: settingsBytes ?? Data(), encoding: .utf8) == "settings")

        let logBytes = try? Data(contentsOf: support
            .appendingPathComponent("logs/abc/buffer.log"))
        #expect(String(data: logBytes ?? Data(), encoding: .utf8) == "log line\nanother line\n")
    }

    // MARK: - Encrypted round-trip

    @Test func encryptedBackupAndRestoreRoundtrip() throws {
        let (support, backup) = tempPair()
        try plant(in: support)
        let key = SymmetricKey(size: .bits256)

        let archive = try BackupService.runBackup(
            supportDir: support, backupDir: backup, key: key)
        #expect(archive.pathExtension == "enc")

        // Magic header check — first 5 bytes match the project-wide PIRC.
        let head = Array(try Data(contentsOf: archive).prefix(5))
        #expect(head == [0x50, 0x49, 0x52, 0x43, 0x01])

        // Verify with the right key.
        let v = try BackupService.verifyArchive(at: archive, key: key)
        #expect(v.fileCount >= 3)
        #expect(v.isEncryptedArchive == true)

        // Verify with the WRONG key — must reject.
        let wrongKey = SymmetricKey(size: .bits256)
        do {
            _ = try BackupService.verifyArchive(at: archive, key: wrongKey)
            Issue.record("Verify should have thrown decryptFailed for the wrong key")
        } catch BackupService.RestoreError.decryptFailed {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        // Verify without a key (encrypted archive needs one).
        do {
            _ = try BackupService.verifyArchive(at: archive, key: nil)
            Issue.record("Verify should have thrown missingKeyForEncryptedArchive")
        } catch BackupService.RestoreError.missingKeyForEncryptedArchive {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        // Wipe + restore with the right key.
        for entry in try FileManager.default.contentsOfDirectory(
            at: support, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: entry)
        }
        try BackupService.restore(from: archive, into: support, key: key)
        let settingsBytes = try? Data(contentsOf: support.appendingPathComponent("settings.json"))
        #expect(String(data: settingsBytes ?? Data(), encoding: .utf8) == "settings")
    }

    // MARK: - Retention

    @Test func trimRemovesFilesOlderThanRetentionWindow() throws {
        let (support, backup) = tempPair()
        try plant(in: support)
        // Three backups planted with synthetic mtimes covering both sides
        // of the retention boundary.
        let now = Date()
        let oldName = "PurpleIRC-2026-03-01-120000.zip"
        let midName = "PurpleIRC-2026-04-15-120000.zip"
        let newName = "PurpleIRC-\(yyyyMMddHHmmss(now)).zip"
        for name in [oldName, midName, newName] {
            try Data().write(to: backup.appendingPathComponent(name))
        }
        try setMTime(at: backup.appendingPathComponent(oldName),
                     to: now.addingTimeInterval(-50 * 86400))
        try setMTime(at: backup.appendingPathComponent(midName),
                     to: now.addingTimeInterval(-15 * 86400))
        try setMTime(at: backup.appendingPathComponent(newName),
                     to: now)

        let removed = BackupService.trimOldBackups(in: backup, retentionDays: 30)
        #expect(removed == 1)
        let remaining = (try FileManager.default.contentsOfDirectory(
            at: backup, includingPropertiesForKeys: nil))
            .map { $0.lastPathComponent }.sorted()
        #expect(remaining.contains(midName))
        #expect(remaining.contains(newName))
        #expect(!remaining.contains(oldName))
    }

    @Test func trimZeroRetentionKeepsEverything() throws {
        let (_, backup) = tempPair()
        try Data().write(to: backup.appendingPathComponent("PurpleIRC-old.zip"))
        let removed = BackupService.trimOldBackups(in: backup, retentionDays: 0)
        #expect(removed == 0)
    }

    @Test func trimIgnoresUnrelatedFiles() throws {
        let (_, backup) = tempPair()
        try Data().write(to: backup.appendingPathComponent("not-a-backup.zip"))
        try Data().write(to: backup.appendingPathComponent("README.txt"))
        let removed = BackupService.trimOldBackups(in: backup, retentionDays: 0)
        #expect(removed == 0)
        // Both unrelated files must still be present.
        let names = (try FileManager.default.contentsOfDirectory(
            at: backup, includingPropertiesForKeys: nil))
            .map { $0.lastPathComponent }.sorted()
        #expect(names.contains("README.txt"))
        #expect(names.contains("not-a-backup.zip"))
    }

    // MARK: - List

    @Test func listBackupsReturnsNewestFirst() throws {
        let (_, backup) = tempPair()
        let now = Date()
        try Data().write(to: backup.appendingPathComponent("PurpleIRC-A.zip"))
        try Data().write(to: backup.appendingPathComponent("PurpleIRC-B.zip"))
        try setMTime(at: backup.appendingPathComponent("PurpleIRC-A.zip"),
                     to: now.addingTimeInterval(-3600))
        try setMTime(at: backup.appendingPathComponent("PurpleIRC-B.zip"), to: now)

        let entries = BackupService.listBackups(in: backup)
        #expect(entries.count == 2)
        #expect(entries.first?.url.lastPathComponent == "PurpleIRC-B.zip")  // newest first
    }

    // MARK: - Factory reset

    @Test func factoryResetWipesSupportDir() throws {
        let (support, _) = tempPair()
        try plant(in: support)
        let before = (try? FileManager.default.contentsOfDirectory(
            at: support, includingPropertiesForKeys: nil).count) ?? 0
        #expect(before > 0)

        let removed = try FactoryReset.wipe(supportDir: support)
        #expect(removed > 0)

        let after = (try? FileManager.default.contentsOfDirectory(
            at: support, includingPropertiesForKeys: nil).count) ?? -1
        #expect(after == 0)
    }

    @Test func factoryResetRefusesNonPurpleIRCDirectory() throws {
        let dangerous = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportantStuff-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: dangerous, withIntermediateDirectories: true)
        try Data("precious".utf8).write(
            to: dangerous.appendingPathComponent("file.txt"))

        // Should refuse and remove nothing.
        let removed = try FactoryReset.wipe(supportDir: dangerous)
        #expect(removed == 0)
        let stillThere = FileManager.default.fileExists(
            atPath: dangerous.appendingPathComponent("file.txt").path)
        #expect(stillThere == true)
    }

    // MARK: - Helpers

    private func setMTime(at url: URL, to date: Date) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: date], ofItemAtPath: url.path)
    }

    private func yyyyMMddHHmmss(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: date)
    }
}
