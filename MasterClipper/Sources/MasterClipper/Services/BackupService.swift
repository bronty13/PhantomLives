import Foundation
import GRDB

@MainActor
enum BackupService {

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
    /// last 60s. Errors are swallowed (logged) — the app should never refuse
    /// to launch because backup failed.
    static func runIfEnabled(settingsStore: SettingsStore) {
        guard settingsStore.settings.autoBackupEnabled else { return }
        if let last = parseISO(settingsStore.settings.lastBackupAt),
           Date().timeIntervalSince(last) < 60 {
            return
        }

        Task.detached(priority: .background) {
            await MainActor.run {
                try? doBackup(settingsStore: settingsStore)
            }
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
            .appendingPathComponent("masterclipper-backup-\(UUID().uuidString).zip")
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

        let outURL = backupDir.appendingPathComponent("MasterClipper-\(stamp).zip")
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
        where url.lastPathComponent.hasPrefix("MasterClipper-") && url.pathExtension == "zip" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantFuture
            if modified < cutoff, (try? fm.removeItem(at: url)) != nil {
                removed += 1
            }
        }
        return removed
    }

    // MARK: - Verify / restore

    enum RestoreError: Error, LocalizedError {
        case unzipFailed(String)
        case missingDatabase
        case invalidDatabase(String)

        var errorDescription: String? {
            switch self {
            case .unzipFailed(let s):     return "Couldn't unzip backup: \(s)"
            case .missingDatabase:        return "Backup didn't contain masterclipper.sqlite"
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
        let clipCount: Int
        let personaCount: Int
        let siteCount: Int
        let postingCount: Int
        let categoryCount: Int
        let calendarEventCount: Int
        let entries: [String]
    }

    /// Non-destructive: extract the archive to a temp directory, validate it
    /// contains a working `masterclipper.sqlite`, count rows, and return a
    /// summary the UI can show before the user commits to a real restore.
    static func verifyArchive(at archiveURL: URL) throws -> VerifyResult {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("mc-verify-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try unzip(archiveURL: archiveURL, to: staging)

        // File walk for byte counts + sample entries
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

        // Validate the SQLite file itself
        let dbCandidate = staging.appendingPathComponent("masterclipper.sqlite")
        guard fm.fileExists(atPath: dbCandidate.path) else {
            throw RestoreError.missingDatabase
        }

        var migrations: [String] = []
        var clipCount = 0
        var personaCount = 0
        var siteCount = 0
        var postingCount = 0
        var categoryCount = 0
        var calendarEventCount = 0

        do {
            let pool = try DatabasePool(path: dbCandidate.path)
            try pool.read { db in
                migrations = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
                clipCount          = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clips")            ?? 0
                personaCount       = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM personas")         ?? 0
                siteCount          = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sites")            ?? 0
                postingCount       = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clip_postings")    ?? 0
                categoryCount      = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM categories")       ?? 0
                calendarEventCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM calendar_events")  ?? 0
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
            clipCount: clipCount,
            personaCount: personaCount,
            siteCount: siteCount,
            postingCount: postingCount,
            categoryCount: categoryCount,
            calendarEventCount: calendarEventCount,
            entries: entries.sorted()
        )
    }

    /// Destructive: replace the support directory contents with the unpacked
    /// archive. Caller is responsible for closing the existing GRDB pool
    /// before calling and reopening it after.
    ///
    /// Files in the support dir are deleted (not the dir itself). The archive
    /// is extracted to a staging dir first, then atomically moved in.
    static func restoreArchive(at archiveURL: URL, into supportDir: URL) throws {
        let fm = FileManager.default

        // Pre-flight verify — throws on garbage archives so we never wipe state
        // for a broken zip.
        _ = try verifyArchive(at: archiveURL)

        let staging = fm.temporaryDirectory
            .appendingPathComponent("mc-restore-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try unzip(archiveURL: archiveURL, to: staging)

        // Wipe support dir contents (preserve the directory)
        if let contents = try? fm.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil) {
            for url in contents {
                try? fm.removeItem(at: url)
            }
        }

        // Move staging contents into support dir
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

    static func listBackups(in backupDir: URL) -> [(url: URL, modified: Date, size: Int)] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return [] }
        var rows: [(URL, Date, Int)] = []
        for url in contents
        where url.lastPathComponent.hasPrefix("MasterClipper-") && url.pathExtension == "zip" {
            let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modified = resourceValues?.contentModificationDate ?? .distantPast
            let size = resourceValues?.fileSize ?? 0
            rows.append((url, modified, size))
        }
        return rows.sorted { $0.1 > $1.1 }
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
