import Foundation

/// Auto-backup service for SlackSucker.
///
/// PhantomLives convention (`PhantomLives/CLAUDE.md`): every app that
/// owns persistent user data must run an automatic backup on launch.
/// Default location: `~/Downloads/SlackSucker backup/`. Default
/// retention: 14 days. Skipped if the last successful backup is under 5
/// minutes old (debounce). Failures are logged via `NSLog`, never thrown
/// — the app must launch even if backup fails.
///
/// Modeled on `Timeliner/Sources/Timeliner/Services/BackupService.swift`.
/// We don't ship a SQLite database; we only back up the JSON state
/// (settings, runs, presets, channel cache).
@MainActor
enum BackupService {

    static let debounceSeconds: TimeInterval = 5 * 60
    static let archivePrefix = "SlackSucker-"
    static let defaultRetentionDays = 14

    enum BackupKeys {
        static let enabled       = "autoBackupEnabled"
        static let path          = "backupPath"
        static let retentionDays = "backupRetentionDays"
        static let lastBackupAt  = "lastBackupAt"
    }

    /// `~/Downloads/SlackSucker backup/`. Created on demand.
    static var defaultBackupDir: URL {
        let downloads = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads")
        return downloads.appendingPathComponent("SlackSucker backup", isDirectory: true)
    }

    static var resolvedBackupDir: URL {
        let raw = UserDefaults.standard.string(forKey: BackupKeys.path)
        if let raw, !raw.isEmpty {
            return URL(fileURLWithPath: raw, isDirectory: true)
        }
        return defaultBackupDir
    }

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

    static func runOnLaunchIfDue() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            BackupKeys.enabled: true,
            BackupKeys.retentionDays: defaultRetentionDays
        ])
        guard defaults.bool(forKey: BackupKeys.enabled) else { return }
        if let last = parseISO(defaults.string(forKey: BackupKeys.lastBackupAt) ?? ""),
           Date().timeIntervalSince(last) < debounceSeconds {
            return
        }
        do {
            let url = try doBackup()
            NSLog("SlackSucker: backup-on-launch wrote \(url.lastPathComponent)")
        } catch {
            NSLog("SlackSucker: backup-on-launch failed — \(error.localizedDescription)")
        }
    }

    @discardableResult
    static func doBackup() throws -> URL {
        let supportDir = AppSupport.directory
        let backupDir  = resolvedBackupDir
        let url = try runBackup(supportDir: supportDir, backupDir: backupDir)
        let retention = UserDefaults.standard.object(forKey: BackupKeys.retentionDays) as? Int
            ?? defaultRetentionDays
        _ = trimOldBackups(in: backupDir, retentionDays: retention)
        UserDefaults.standard.set(isoNow(), forKey: BackupKeys.lastBackupAt)
        return url
    }

    @discardableResult
    static func runBackup(supportDir: URL, backupDir: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let stamp = timestamp()
        let tempZip = fm.temporaryDirectory
            .appendingPathComponent("slacksucker-backup-\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: tempZip) }

        try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)

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

        // `zip -rqX .` against an empty support dir may not create the
        // file; write a zero-byte marker so the listing/retention paths
        // have something to operate on (the "first launch with no data"
        // case).
        if !fm.fileExists(atPath: tempZip.path) {
            try Data().write(to: tempZip)
        }

        let zipData = try Data(contentsOf: tempZip)
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
        case invalidContents(String)

        var errorDescription: String? {
            switch self {
            case .unzipFailed(let s):    return "Couldn't unzip backup: \(s)"
            case .invalidContents(let s): return "Backup contents look invalid: \(s)"
            }
        }
    }

    struct VerifyResult {
        let archiveURL: URL
        let archiveSize: Int
        let fileCount: Int
        let totalBytes: Int64
        let runHistoryCount: Int
        let presetCount: Int
        let entries: [String]
    }

    static func verifyArchive(at archiveURL: URL) throws -> VerifyResult {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("slacksucker-verify-\(UUID().uuidString)", isDirectory: true)
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

        var runs = 0, presets = 0
        let runsURL    = staging.appendingPathComponent("runs.json")
        let presetsURL = staging.appendingPathComponent("presets.json")
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: runsURL),
           let rows = try? dec.decode([RunHistoryEntry].self, from: data) {
            runs = rows.count
        }
        if let data = try? Data(contentsOf: presetsURL),
           let rows = try? dec.decode([ArchivePreset].self, from: data) {
            presets = rows.count
        }

        let archiveSize = (try? fm.attributesOfItem(atPath: archiveURL.path)[.size] as? Int) ?? 0
        return VerifyResult(
            archiveURL: archiveURL,
            archiveSize: archiveSize,
            fileCount: fileCount,
            totalBytes: totalBytes,
            runHistoryCount: runs,
            presetCount: presets,
            entries: entries.sorted()
        )
    }

    static func restoreArchive(at archiveURL: URL, into supportDir: URL = AppSupport.directory) throws {
        let fm = FileManager.default
        _ = try verifyArchive(at: archiveURL)

        let staging = fm.temporaryDirectory
            .appendingPathComponent("slacksucker-restore-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try unzip(archiveURL: archiveURL, to: staging)

        if let contents = try? fm.contentsOfDirectory(at: supportDir, includingPropertiesForKeys: nil) {
            for url in contents {
                try? fm.removeItem(at: url)
            }
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

    static func parseISO(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: s)
    }

    static func formatBytes(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }
}
