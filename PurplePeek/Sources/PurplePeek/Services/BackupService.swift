import Foundation
import GRDB

/// Auto-backup service for PurplePeek (PhantomLives auto-backup-on-launch standard).
///
/// On launch, zips `~/Library/Application Support/PurplePeek/` into
/// `~/Downloads/PurplePeek backup/PurplePeek-yyyy-MM-dd-HHmmss.zip`. Retention defaults to
/// 14 days; the run is debounced (skipped if the last success is under 5 minutes old) and
/// never throws out of `runOnLaunchIfDue` — the app must always launch.
@MainActor
enum BackupService {

    static let debounceSeconds: TimeInterval = 5 * 60
    static let archivePrefix = "PurplePeek-"

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
        if let lastStr = settingsStore.settings.lastBackupAt,
           let last = parseISO(lastStr),
           Date().timeIntervalSince(last) < debounceSeconds {
            return
        }
        do {
            let url = try doBackup(settingsStore: settingsStore)
            NSLog("PurplePeek: backup-on-launch wrote \(url.lastPathComponent)")
        } catch {
            NSLog("PurplePeek: backup-on-launch failed — \(error.localizedDescription)")
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
            .appendingPathComponent("purplepeek-backup-\(UUID().uuidString).zip")
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

    static func parseISO(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: s)
    }
}
