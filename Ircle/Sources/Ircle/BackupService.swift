import Foundation

/// Auto-backup service for Ircle.
///
/// PhantomLives convention: every app that owns persistent user data runs an
/// automatic backup on launch. Default location: `~/Downloads/Ircle backup/`.
/// Default retention: 14 days. Backup is debounced — skipped if the last
/// successful backup is under 5 minutes old. The user can override the
/// directory and retention in Settings → Backup.
///
/// Ircle's user data is a JSON document (`settings.json`: server profiles,
/// credentials, appearance) under Application Support — the user can't easily
/// recreate it, so it's in scope for the standard.
@MainActor
enum BackupService {

    /// Skip auto-backup if the last successful run is under this many seconds
    /// old — keeps debugging relaunches from filling the backup folder.
    static let debounceSeconds: TimeInterval = 5 * 60

    /// Archive name format: `Ircle-yyyy-MM-dd-HHmmss.zip`. The prefix lets the
    /// retention trim and listing UI scope to "our" archives.
    static let archivePrefix = "Ircle-"

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

    /// Run a backup if enabled AND outside the debounce window. Errors are
    /// swallowed (logged via NSLog) — the app must never refuse to launch
    /// because backup failed.
    static func runOnLaunchIfDue(settingsStore: SettingsStore) {
        guard settingsStore.settings.autoBackupEnabled else { return }
        if let last = parseISO(settingsStore.settings.lastBackupAt),
           Date().timeIntervalSince(last) < debounceSeconds {
            return
        }
        do {
            let url = try doBackup(settingsStore: settingsStore)
            NSLog("Ircle: backup-on-launch wrote \(url.lastPathComponent)")
        } catch {
            NSLog("Ircle: backup-on-launch failed — \(error.localizedDescription)")
        }
    }

    @discardableResult
    static func doBackup(settingsStore: SettingsStore) throws -> URL {
        let supportDir = SettingsStore.supportDirectory
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
        // Application Support may not exist yet on a brand-new install; make it
        // so the zip always has a directory to archive.
        try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)

        let stamp = timestamp()
        let tempZip = fm.temporaryDirectory
            .appendingPathComponent("ircle-backup-\(UUID().uuidString).zip")
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
            let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            rows.append((url, rv?.contentModificationDate ?? .distantPast, rv?.fileSize ?? 0))
        }
        return rows.sorted { $0.1 > $1.1 }
    }

    // MARK: - Verify / restore

    enum RestoreError: Error, LocalizedError {
        case unzipFailed(String)
        case missingSettings
        var errorDescription: String? {
            switch self {
            case .unzipFailed(let s): return "Couldn't unzip backup: \(s)"
            case .missingSettings:    return "Backup didn't contain settings.json"
            }
        }
    }

    struct VerifyResult {
        let archiveURL: URL
        let archiveSize: Int
        let fileCount: Int
        let totalBytes: Int64
        let hasSettings: Bool
        let serverCount: Int
        let entries: [String]
    }

    /// Non-destructive: unpack to a temp dir, confirm `settings.json` is present
    /// and decodes, return a summary the UI shows before a real restore.
    static func verifyArchive(at archiveURL: URL) throws -> VerifyResult {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("ircle-verify-\(UUID().uuidString)", isDirectory: true)
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

        let settingsURL = staging.appendingPathComponent("settings.json")
        guard fm.fileExists(atPath: settingsURL.path) else {
            throw RestoreError.missingSettings
        }
        var serverCount = 0
        if let data = try? Data(contentsOf: settingsURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            serverCount = decoded.servers.count
        }

        let archiveSize = (try? fm.attributesOfItem(atPath: archiveURL.path)[.size] as? Int) ?? 0
        return VerifyResult(
            archiveURL: archiveURL,
            archiveSize: archiveSize,
            fileCount: fileCount,
            totalBytes: totalBytes,
            hasSettings: true,
            serverCount: serverCount,
            entries: entries.sorted()
        )
    }

    /// Destructive: replace the support directory contents with the archive,
    /// after taking a `Ircle-pre-restore-…zip` safety backup.
    static func restoreArchive(at archiveURL: URL, into supportDir: URL,
                               safetyBackupDir: URL) throws {
        let fm = FileManager.default
        _ = try verifyArchive(at: archiveURL) // throws on garbage — never wipe for a broken zip

        // Safety backup first.
        if let safety = try? runBackup(supportDir: supportDir, backupDir: safetyBackupDir) {
            let renamed = safetyBackupDir.appendingPathComponent(
                "Ircle-pre-restore-\(timestamp()).zip")
            try? fm.moveItem(at: safety, to: renamed)
        }

        let staging = fm.temporaryDirectory
            .appendingPathComponent("ircle-restore-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        try unzip(archiveURL: archiveURL, to: staging)

        try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
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

    static func isoNow() -> String {
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
