import Foundation
import GRDB

/// Auto-backup service for PurpleTracker. Implements the PhantomLives
/// auto-backup-on-launch convention from CLAUDE.md, with a 30-day default
/// retention (per the PurpleTracker spec).
///
///   • Default location: `~/Downloads/PurpleTracker/Backup/`
///   • Filename: `PurpleTracker-YYYY-MM-DD-HHmmss.zip`
///   • Contents: zip of the entire Application Support/PurpleTracker directory
///   • Retention: 30 days by default; `0` keeps forever
///   • Debounce: skip if last successful backup is < 5 minutes old
///   • Failure: NSLog only — the app must launch even if backup fails
@MainActor
enum BackupService {

    static let debounceSeconds: TimeInterval = 5 * 60
    static let archivePrefix = "PurpleTracker-"

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

    static func runOnLaunchIfDue(settingsStore: SettingsStore) {
        guard settingsStore.settings.autoBackupEnabled else { return }
        if let last = parseISO(settingsStore.settings.lastBackupAt),
           Date().timeIntervalSince(last) < debounceSeconds {
            return
        }
        do {
            let url = try doBackup(settingsStore: settingsStore)
            NSLog("PurpleTracker: backup-on-launch wrote \(url.lastPathComponent)")
        } catch {
            NSLog("PurpleTracker: backup-on-launch failed — \(error.localizedDescription)")
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
        // Make sure the source directory exists so /usr/bin/zip doesn't bail
        // on a fresh checkout that has never launched the real app.
        try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)

        let stamp = timestamp()
        let tempZip = fm.temporaryDirectory
            .appendingPathComponent("pt-backup-\(UUID().uuidString).zip")
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
            at: backupDir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return 0 }
        var removed = 0
        for url in contents
        where url.lastPathComponent.hasPrefix(archivePrefix) && url.pathExtension == "zip" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantFuture
            if modified < cutoff, (try? fm.removeItem(at: url)) != nil { removed += 1 }
        }
        return removed
    }

    static func listBackups(in backupDir: URL) -> [(url: URL, modified: Date, size: Int)] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: backupDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return [] }
        var rows: [(URL, Date, Int)] = []
        for url in contents
        where url.lastPathComponent.hasPrefix(archivePrefix) && url.pathExtension == "zip" {
            let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            rows.append((url, rv?.contentModificationDate ?? .distantPast, rv?.fileSize ?? 0))
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
            case .missingDatabase:        return "Backup didn't contain purpletracker.sqlite"
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
        let matterCount: Int
        let attachmentCount: Int
        let timeEntryCount: Int
        let entries: [String]
    }

    /// Non-destructive integrity check. Extract to temp, count rows, return.
    static func verifyArchive(at archiveURL: URL) throws -> VerifyResult {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("pt-verify-\(UUID().uuidString)", isDirectory: true)
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

        let dbCandidate = staging.appendingPathComponent("purpletracker.sqlite")
        guard fm.fileExists(atPath: dbCandidate.path) else { throw RestoreError.missingDatabase }

        var migrations: [String] = []
        var matterCount = 0
        var attachmentCount = 0
        var timeEntryCount = 0
        do {
            let pool = try DatabasePool(path: dbCandidate.path)
            try pool.read { db in
                migrations = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
                matterCount     = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM matter")     ?? 0
                attachmentCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM attachment") ?? 0
                timeEntryCount  = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM time_entry") ?? 0
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
            matterCount: matterCount,
            attachmentCount: attachmentCount,
            timeEntryCount: timeEntryCount,
            entries: entries.sorted()
        )
    }

    /// Destructive: replace the support directory contents with the archive's
    /// contents. Caller is responsible for closing GRDB before and reopening
    /// after. A pre-restore safety backup is the caller's job — see
    /// `AppState.restoreBackup(_:)`.
    static func restoreArchive(at archiveURL: URL, into supportDir: URL) throws {
        let fm = FileManager.default
        _ = try verifyArchive(at: archiveURL)
        let staging = fm.temporaryDirectory
            .appendingPathComponent("pt-restore-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try unzip(archiveURL: archiveURL, to: staging)

        if let contents = try? fm.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil) {
            for url in contents { try? fm.removeItem(at: url) }
        }
        try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
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
        do { try proc.run() } catch { throw RestoreError.unzipFailed(error.localizedDescription) }
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let err = String(data: stderrPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            throw RestoreError.unzipFailed("exit \(proc.terminationStatus): \(err)")
        }
    }

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
