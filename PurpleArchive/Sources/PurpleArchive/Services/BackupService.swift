import Foundation

/// Auto-backup-on-launch (PhantomLives standard). Zips
/// `~/Library/Application Support/PurpleArchive/` (settings, recents, future
/// password-vault references) → `~/Downloads/PurpleArchive backup/`, 14-day
/// retention, 5-minute debounce, never throws on the launch path. Mirrors the
/// Timeliner reference implementation.
@MainActor
enum BackupService {
    static let debounceSeconds: TimeInterval = 5 * 60
    static let archivePrefix = "PurpleArchive-"

    enum BackupError: Error, LocalizedError {
        case zipFailed(status: Int32, stderr: String)
        case noBytes
        var errorDescription: String? {
            switch self {
            case .zipFailed(let s, let err): return "zip exited \(s): \(err)"
            case .noBytes: return "Empty archive — nothing was written."
            }
        }
    }

    /// Run a backup if enabled and outside the debounce window. Swallows errors
    /// (NSLog) — the app must never refuse to launch because backup failed.
    static func runOnLaunchIfDue(settingsStore: SettingsStore) {
        guard settingsStore.settings.autoBackupEnabled else { return }
        if let last = parseISO(settingsStore.settings.lastBackupAt),
           Date().timeIntervalSince(last) < debounceSeconds { return }
        do {
            let url = try doBackup(settingsStore: settingsStore)
            NSLog("PurpleArchive: backup-on-launch wrote \(url.lastPathComponent)")
        } catch {
            NSLog("PurpleArchive: backup-on-launch failed — \(error.localizedDescription)")
        }
    }

    @discardableResult
    static func doBackup(settingsStore: SettingsStore) throws -> URL {
        let url = try runBackup(supportDir: SettingsStore.supportDirectory,
                                backupDir: settingsStore.resolvedBackupPath)
        _ = trimOldBackups(in: settingsStore.resolvedBackupPath,
                           retentionDays: settingsStore.settings.backupRetentionDays)
        settingsStore.settings.lastBackupAt = isoNow()
        settingsStore.save()
        return url
    }

    @discardableResult
    static func runBackup(supportDir: URL, backupDir: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let stamp = timestamp()
        let tempZip = fm.temporaryDirectory.appendingPathComponent("pa-backup-\(UUID().uuidString).zip")
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
            at: backupDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return 0 }
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

    /// Restore: replace the support directory contents with the unpacked backup.
    static func restoreArchive(at archiveURL: URL, into supportDir: URL) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("pa-restore-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-q", "-o", archiveURL.path, "-d", staging.path]
        try proc.run(); proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw BackupError.zipFailed(status: proc.terminationStatus, stderr: "unzip failed")
        }
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

    // MARK: - Helpers

    private static func timestamp() -> String { format("yyyy-MM-dd-HHmmss") }
    static func isoNow() -> String { format("yyyy-MM-dd'T'HH:mm:ss") }
    static func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f.date(from: s)
    }
    private static func format(_ fmt: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = fmt; return f.string(from: Date())
    }
}
