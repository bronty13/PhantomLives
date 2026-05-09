import Foundation

/// Auto-backup service for PurpleDedup.
///
/// PhantomLives convention: every app that owns persistent user data runs an automatic
/// backup on launch. Default location: `~/Downloads/PurpleDedup backup/`. Default
/// retention: 14 days. Debounced — skipped if the last successful backup is < 5 minutes
/// old. Modeled on `Timeliner/Sources/Timeliner/Services/BackupService.swift`; see that
/// file for the canonical reference implementation.
///
/// Phase 1: this service exists and is unit-tested. The launch-time auto-run is wired up
/// once the SwiftUI app gets a Settings pane (Phase 4); until then, callers can invoke
/// `runBackup` manually. Logged in HANDOFF.md as a deliberate gap.
public enum BackupService {

    /// Skip auto-backup if the last successful run is less than this many seconds old.
    public static let debounceSeconds: TimeInterval = 5 * 60

    /// Filename prefix for archives written by this service. Format:
    /// `PurpleDedup-yyyy-MM-dd-HHmmss.zip`. Used by the retention trim and listing UI to
    /// recognize "our" archives without nuking unrelated zips a user dropped here.
    public static let archivePrefix = "PurpleDedup-"

    public enum BackupError: Error, LocalizedError {
        case zipFailed(status: Int32, stderr: String)
        case noBytes

        public var errorDescription: String? {
            switch self {
            case .zipFailed(let s, let err): return "zip exited \(s): \(err)"
            case .noBytes:                   return "Empty archive — nothing was written."
            }
        }
    }

    @discardableResult
    public static func runBackup(supportDir: URL, backupDir: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let stamp = timestamp()
        let tempZip = fm.temporaryDirectory
            .appendingPathComponent("purplededup-backup-\(UUID().uuidString).zip")
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
        Log.backup.info("Wrote backup \(outURL.lastPathComponent, privacy: .public)")
        return outURL
    }

    @discardableResult
    public static func trimOldBackups(in backupDir: URL, retentionDays: Int) -> Int {
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

    public static func listBackups(in backupDir: URL) -> [(url: URL, modified: Date, size: Int)] {
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

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }
}
