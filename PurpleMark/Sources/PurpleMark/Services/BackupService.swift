import Foundation
import AppKit

/// Launch-time auto-backup for PurpleMark.
///
/// PurpleMark edits user-owned `.md` files in place, so its *documents* are not
/// what's at risk — they live wherever the user keeps them. What this service
/// protects is PurpleMark's **own** state: a JSON snapshot of preferences and
/// the recent-files list, written into the support directory and zipped to
/// `~/Downloads/PurpleMark backup/`. Per the PhantomLives standard: 14-day
/// retention, 5-minute debounce, never throws out of the launch path.
@MainActor
enum BackupService {
    static let debounceSeconds: TimeInterval = 5 * 60
    static let archivePrefix = "PurpleMark-"

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("PurpleMark", isDirectory: true)
    }

    static func defaultBackupDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/PurpleMark backup", isDirectory: true)
    }

    static func resolvedBackupDirectory(_ settings: AppSettings) -> URL {
        settings.backupDirectoryPath.isEmpty
            ? defaultBackupDirectory()
            : URL(fileURLWithPath: settings.backupDirectoryPath, isDirectory: true)
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

    /// Entry point from app launch. Swallows all errors (logs via NSLog) — the
    /// app must never fail to launch because a backup failed.
    static func runOnLaunchIfDue(settings: AppSettings) {
        guard settings.autoBackupEnabled else { return }
        if let last = parseISO(settings.lastBackupAt),
           Date().timeIntervalSince(last) < debounceSeconds {
            return
        }
        do {
            let url = try doBackup(settings: settings)
            NSLog("PurpleMark: backup-on-launch wrote \(url.lastPathComponent)")
        } catch {
            NSLog("PurpleMark: backup-on-launch failed — \(error.localizedDescription)")
        }
    }

    @discardableResult
    static func doBackup(settings: AppSettings) throws -> URL {
        try snapshotState()
        let backupDir = resolvedBackupDirectory(settings)
        let url = try runBackup(supportDir: supportDirectory, backupDir: backupDir)
        _ = trimOldBackups(in: backupDir, retentionDays: settings.backupRetentionDays)
        settings.lastBackupAt = isoNow()
        return url
    }

    /// Writes a JSON snapshot of preferences + recent files into the support
    /// directory so the archive has meaningful, restorable contents.
    static func snapshotState() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let prefs = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "com.bronty13.PurpleMark") ?? [:]
        // Keep only JSON-serializable scalar prefs.
        var clean: [String: Any] = [:]
        for (k, v) in prefs where (v is String || v is NSNumber || v is Bool) {
            clean[k] = v
        }
        let recents = NSDocumentController.shared.recentDocumentURLs.map { $0.path }
        let payload: [String: Any] = ["preferences": clean, "recentDocuments": recents]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: supportDirectory.appendingPathComponent("state.json"), options: .atomic)
    }

    @discardableResult
    static func runBackup(supportDir: URL, backupDir: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let stamp = timestamp()
        let tempZip = fm.temporaryDirectory
            .appendingPathComponent("purplemark-backup-\(UUID().uuidString).zip")
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
            at: backupDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return [] }
        var rows: [(URL, Date, Int)] = []
        for url in contents
        where url.lastPathComponent.hasPrefix(archivePrefix) && url.pathExtension == "zip" {
            let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            rows.append((url, rv?.contentModificationDate ?? .distantPast, rv?.fileSize ?? 0))
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
