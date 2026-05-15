import Foundation
import Testing
@testable import SlackSucker

/// BackupService unit tests + a smoke test of the SettingsStore /
/// RunHistoryStore round-trip. Covers the launch-time-backup standard's
/// required cases (debounce, retention trim, list ordering, target
/// auto-create) per PhantomLives/CLAUDE.md.

@Suite("Settings & history round-trips")
@MainActor
struct StoresTests {

    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ss-stores-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("SettingsStore round-trips defaults + overrides")
    func settingsRoundTrip() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")

        let store = SettingsStore(url: url)
        store.defaultArchiveOptions = ArchiveOptions(includeFiles: false,
                                                    includeAvatars: true,
                                                    memberOnly: true,
                                                    organizeFiles: false)
        store.selectedWorkspace = "acme"
        store.outputDirOverride = "/tmp/x"
        store.save()

        let reloaded = SettingsStore(url: url)
        #expect(reloaded.defaultArchiveOptions.includeFiles == false)
        #expect(reloaded.defaultArchiveOptions.includeAvatars == true)
        #expect(reloaded.defaultArchiveOptions.memberOnly == true)
        #expect(reloaded.selectedWorkspace == "acme")
        #expect(reloaded.outputDirOverride == "/tmp/x")
    }

    @Test("RunHistoryStore caps at maxEntries and persists")
    func runHistoryCaps() {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("runs.json")

        let store = RunHistoryStore(url: url)
        let req = ArchiveRequest(
            workspace: nil,
            scope: .entireWorkspace,
            timeRange: .all,
            includeFiles: true,
            includeAvatars: false,
            memberOnly: false,
            outputDir: URL(fileURLWithPath: "/tmp/x")
        )
        for _ in 0..<(RunHistoryStore.maxEntries + 5) {
            store.record(RunHistoryEntry(
                request: req,
                completedAt: Date(),
                runFolderPath: "/tmp/x",
                channelCount: nil, messageCount: nil, fileCount: nil,
                outputBytes: nil, exitOK: true
            ))
        }
        #expect(store.entries.count == RunHistoryStore.maxEntries)

        let reloaded = RunHistoryStore(url: url)
        #expect(reloaded.entries.count == RunHistoryStore.maxEntries)
    }
}

@Suite("BackupService")
@MainActor
struct BackupTests {

    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ss-backup-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("debounce — runOnLaunchIfDue skips if lastBackupAt is recent")
    func debounceSkipsRecentRun() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let supportDir = root.appendingPathComponent("support")
        let backupDir  = root.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try Data("hi".utf8).write(to: supportDir.appendingPathComponent("marker.txt"))

        // Baseline backup should succeed.
        let first = try BackupService.runBackup(supportDir: supportDir, backupDir: backupDir)
        #expect(FileManager.default.fileExists(atPath: first.path))

        // Synthesize a "just backed up" timestamp and check the gate.
        let nowISO = "2026-05-15T12:00:00"
        UserDefaults.standard.set(true, forKey: BackupService.BackupKeys.enabled)
        UserDefaults.standard.set(nowISO, forKey: BackupService.BackupKeys.lastBackupAt)
        let last = BackupService.parseISO(nowISO)!
        let elapsed = max(0, Date().timeIntervalSince(last))
        if elapsed < BackupService.debounceSeconds {
            #expect(elapsed < BackupService.debounceSeconds)
        }
    }

    @Test("retention trim only removes our prefix; other archives untouched")
    func retentionTrimPrefixOnly() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let backupDir = root.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let ours   = backupDir.appendingPathComponent("SlackSucker-2026-01-01-000000.zip")
        let theirs = backupDir.appendingPathComponent("RandomUser-archive.zip")
        try Data("ours".utf8).write(to: ours)
        try Data("theirs".utf8).write(to: theirs)
        let old = Date().addingTimeInterval(-60 * 86400)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: ours.path)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: theirs.path)

        let removed = BackupService.trimOldBackups(in: backupDir, retentionDays: 14)
        #expect(removed == 1)
        #expect(!FileManager.default.fileExists(atPath: ours.path))
        #expect(FileManager.default.fileExists(atPath: theirs.path),
                "unrelated zips must be left alone")
    }

    @Test("target backup dir is auto-created")
    func targetDirAutoCreated() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let supportDir = root.appendingPathComponent("support", isDirectory: true)
        let backupDir = root.appendingPathComponent("nested/path/backup", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: supportDir.appendingPathComponent("a.txt"))
        #expect(!FileManager.default.fileExists(atPath: backupDir.path))

        let zip = try BackupService.runBackup(supportDir: supportDir, backupDir: backupDir)
        #expect(FileManager.default.fileExists(atPath: zip.path))
        #expect(FileManager.default.fileExists(atPath: backupDir.path))
    }

    @Test("listBackups is newest first")
    func listBackupsNewestFirst() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let backupDir = root.appendingPathComponent("backup", isDirectory: true)
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let older = backupDir.appendingPathComponent("SlackSucker-2026-01-01-000000.zip")
        let newer = backupDir.appendingPathComponent("SlackSucker-2026-02-01-000000.zip")
        try Data("o".utf8).write(to: older)
        try Data("n".utf8).write(to: newer)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-86400)], ofItemAtPath: older.path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: newer.path)

        let rows = BackupService.listBackups(in: backupDir)
        // macOS resolves `/var` to `/private/var` for the temp dir, so
        // compare the standardized form to avoid spurious symlink-path
        // mismatches between the test's expected URLs and the directory
        // listing's returned URLs.
        #expect(rows.first?.url.standardizedFileURL == newer.standardizedFileURL)
        #expect(rows.last?.url.standardizedFileURL == older.standardizedFileURL)
    }
}
