import Foundation
import GRDB

/// Auto-backup service for PurpleDiary.
///
/// PhantomLives convention: every app that owns persistent user data runs an
/// automatic backup on launch. Default location: `~/Downloads/PurpleDiary backup/`.
/// Default retention: 14 days. Backup is debounced — skipped if the last
/// successful backup is under 5 minutes old. The user can override the
/// directory and retention in Settings → Backup.
@MainActor
enum BackupService {

    /// Skip auto-backup if the last successful run is less than this many
    /// seconds old. Prevents repeated relaunches during a debugging session
    /// from filling the backup folder.
    static let debounceSeconds: TimeInterval = 5 * 60

    /// Filename prefix for archives written by this service. The archive name
    /// format is `PurpleDiary-yyyy-MM-dd-HHmmss.zip`. Used by both the
    /// retention trim and the listing UI to recognize "our" archives.
    static let archivePrefix = "PurpleDiary-"

    enum BackupError: Error, LocalizedError {
        case zipFailed(status: Int32, stderr: String)
        case noBytes

        var errorDescription: String? {
            switch self {
            case .zipFailed(let s, let err): return "zip exited \(s): \(err)"
            case .noBytes:                   return "Empty archive — nothing was written."
            }
        }
    }

    /// Run a backup if it's enabled in settings AND we haven't run one in the
    /// debounce window. Errors are swallowed (logged via NSLog) — the app must
    /// never refuse to launch because backup failed. Public entry point used
    /// from `AppState.init`.
    static func runOnLaunchIfDue(settingsStore: SettingsStore) {
        guard settingsStore.settings.autoBackupEnabled else { return }
        if let last = parseISO(settingsStore.settings.lastBackupAt),
           Date().timeIntervalSince(last) < debounceSeconds {
            return
        }
        do {
            let url = try doBackup(settingsStore: settingsStore)
            NSLog("PurpleDiary: backup-on-launch wrote \(url.lastPathComponent)")
        } catch {
            NSLog("PurpleDiary: backup-on-launch failed — \(error.localizedDescription)")
        }
    }

    @discardableResult
    static func doBackup(settingsStore: SettingsStore) throws -> URL {
        let supportDir = DatabaseService.supportDirectory
        let backupDir = settingsStore.resolvedBackupPath
        let url = try runBackup(supportDir: supportDir, backupDir: backupDir)
        _ = trimOldBackups(in: backupDir, retentionDays: settingsStore.settings.backupRetentionDays)
        var s = settingsStore.settings
        s.lastBackupAt = isoNow()
        settingsStore.settings = s
        settingsStore.save()
        return url
    }

    @discardableResult
    static func runBackup(supportDir: URL, backupDir: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let stamp = timestamp()
        let tempZip = fm.temporaryDirectory
            .appendingPathComponent("purplediary-backup-\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: tempZip) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.arguments = ["-rqX", tempZip.path, ".", "-x", "*.DS_Store"]
        proc.currentDirectoryURL = supportDir
        let stderrPipe = Pipe()
        proc.standardError = stderrPipe
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let err = String(data: stderrPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            throw BackupError.zipFailed(status: proc.terminationStatus, stderr: err)
        }

        let zipData = try Data(contentsOf: tempZip)
        guard !zipData.isEmpty else { throw BackupError.noBytes }

        let outURL = backupDir.appendingPathComponent("\(archivePrefix)\(stamp).zip")
        try zipData.write(to: outURL, options: .atomic)
        return outURL
    }

    @discardableResult
    static func trimOldBackups(in backupDir: URL, retentionDays: Int) -> Int {
        guard retentionDays > 0 else { return 0 }
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
        guard let contents = try? fm.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return 0 }
        var removed = 0
        for url in contents
        where url.lastPathComponent.hasPrefix(archivePrefix) && url.pathExtension == "zip" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantFuture
            if modified < cutoff, (try? fm.removeItem(at: url)) != nil {
                removed += 1
            }
        }
        return removed
    }

    static func listBackups(in backupDir: URL) -> [(url: URL, modified: Date, size: Int)] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return [] }
        var rows: [(URL, Date, Int)] = []
        for url in contents
        where url.lastPathComponent.hasPrefix(archivePrefix) && url.pathExtension == "zip" {
            let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modified = resourceValues?.contentModificationDate ?? .distantPast
            let size = resourceValues?.fileSize ?? 0
            rows.append((url, modified, size))
        }
        return rows.sorted { $0.1 > $1.1 }
    }

    // MARK: - Verify / restore

    enum RestoreError: Error, LocalizedError {
        case unzipFailed(String)
        case missingDatabase
        case invalidDatabase(String)

        var errorDescription: String? {
            switch self {
            case .unzipFailed(let s):     return "Couldn't unzip backup: \(s)"
            case .missingDatabase:        return "Backup didn't contain diary.sqlite"
            case .invalidDatabase(let s): return "Backup database can't be opened: \(s)"
            }
        }
    }

    struct VerifyResult {
        let archiveURL: URL
        let archiveSize: Int
        let fileCount: Int
        let totalBytes: Int64
        let migrations: [String]
        let entryCount: Int
        let tagCount: Int
        let personCount: Int
        let entries: [String]
    }

    /// Non-destructive: extract the archive to a temp directory, validate it
    /// contains a working `diary.sqlite`, count rows, return a summary the UI
    /// can show before the user commits to a real restore.
    static func verifyArchive(at archiveURL: URL) throws -> VerifyResult {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("pd-verify-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try unzip(archiveURL: archiveURL, to: staging)

        var fileCount = 0
        var totalBytes: Int64 = 0
        var entries: [String] = []
        if let enumerator = fm.enumerator(at: staging, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
            for case let url as URL in enumerator {
                let rv = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if rv?.isRegularFile == true {
                    fileCount += 1
                    totalBytes += Int64(rv?.fileSize ?? 0)
                    if entries.count < 25 {
                        entries.append(url.path.replacingOccurrences(of: staging.path + "/", with: ""))
                    }
                }
            }
        }

        let dbCandidate = staging.appendingPathComponent("diary.sqlite")
        guard fm.fileExists(atPath: dbCandidate.path) else {
            throw RestoreError.missingDatabase
        }

        var migrations: [String] = []
        var entryCount = 0
        var tagCount = 0
        var personCount = 0
        do {
            // Open with the live key so an *encrypted* archive (the normal case
            // once at-rest encryption is on) can be read. With no key in scope
            // this is a bare config and plaintext archives still verify.
            let pool = try DatabasePool(path: dbCandidate.path,
                                        configuration: DatabaseService.makeConfiguration())
            try pool.read { db in
                migrations  = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
                entryCount  = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entries") ?? 0
                tagCount    = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags")    ?? 0
                personCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM people")  ?? 0
            }
        } catch {
            throw RestoreError.invalidDatabase(error.localizedDescription)
        }

        let archiveSize = (try? fm.attributesOfItem(atPath: archiveURL.path)[.size] as? Int) ?? 0

        return VerifyResult(
            archiveURL: archiveURL,
            archiveSize: archiveSize,
            fileCount: fileCount,
            totalBytes: totalBytes,
            migrations: migrations,
            entryCount: entryCount,
            tagCount: tagCount,
            personCount: personCount,
            entries: entries.sorted()
        )
    }

    /// Destructive: replace the support directory contents with the unpacked
    /// archive. Always create a pre-restore safety backup first (caller's
    /// responsibility via `doBackup`). Caller must close the GRDB pool before
    /// calling and reopen it after.
    static func restoreArchive(at archiveURL: URL, into supportDir: URL) throws {
        let fm = FileManager.default

        // Pre-flight verify — throws on garbage archives so we never wipe
        // state for a broken zip.
        _ = try verifyArchive(at: archiveURL)

        let staging = fm.temporaryDirectory
            .appendingPathComponent("pd-restore-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try unzip(archiveURL: archiveURL, to: staging)

        if let contents = try? fm.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil) {
            for url in contents { try? fm.removeItem(at: url) }
        }
        if let contents = try? fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) {
            for url in contents {
                let target = supportDir.appendingPathComponent(url.lastPathComponent)
                try? fm.removeItem(at: target)
                try fm.moveItem(at: url, to: target)
            }
        }
    }

    private static func unzip(archiveURL: URL, to dest: URL) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-q", "-o", archiveURL.path, "-d", dest.path]
        let stderrPipe = Pipe()
        proc.standardError = stderrPipe
        do {
            try proc.run()
        } catch {
            throw RestoreError.unzipFailed(error.localizedDescription)
        }
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let err = String(data: stderrPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            throw RestoreError.unzipFailed("exit \(proc.terminationStatus): \(err)")
        }
    }

    // MARK: - Helpers

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }

    private static func isoNow() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: Date())
    }

    private static func parseISO(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: s)
    }
}
