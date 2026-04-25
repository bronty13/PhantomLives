import Foundation
import CryptoKit

/// Compresses + encrypts PurpleIRC's support directory into a single
/// timestamped archive on every launch. Designed to be the safety net
/// the d0cc021 / assistant-rollout incidents needed: any future
/// settings clobber can be rolled back from the most recent backup
/// (still encrypted with the user's keystore DEK, so portability ≠
/// confidentiality loss).
///
/// Output layout:
///   <backupDir>/PurpleIRC-YYYY-MM-DD-HHmmss.zip.enc
///
/// Format: PIRC magic header (5 bytes) + AES-256-GCM-sealed zip payload.
/// Plaintext fallback (no key) writes a bare `.zip` so users without
/// encryption still have something portable.
///
/// `downloads/` is excluded — those are user files transferred via DCC,
/// often large, not really "settings."
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

    /// Run a single backup pass. Errors propagate so the caller can
    /// surface them in the UI; on success returns the URL of the new
    /// archive. Uses `/usr/bin/zip` because it ships with macOS
    /// everywhere and gives us a real ZIP file (Apple Archive Framework
    /// produces `.aar`, not zip).
    @discardableResult
    static func runBackup(supportDir: URL,
                          backupDir: URL,
                          key: SymmetricKey?) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        // Build a unique temp path. Cleaned up via defer no matter what.
        let stamp = timestampString()
        let tempZip = fm.temporaryDirectory
            .appendingPathComponent("purpleirc-backup-\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: tempZip) }

        // Spawn /usr/bin/zip. -r recursive, -q quiet, -X strip extra
        // attributes so backups are stable across runs. Excludes
        // downloads/* and .DS_Store. cwd-relative paths so the archive
        // contents look like ./settings.json rather than absolute paths.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = [
            "-rqX",
            tempZip.path,
            ".",
            "-x", "downloads/*",
            "-x", "*.DS_Store"
        ]
        process.currentDirectoryURL = supportDir
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errBytes = stderrPipe.fileHandleForReading.availableData
            let errStr = String(data: errBytes, encoding: .utf8) ?? ""
            throw BackupError.zipFailed(status: process.terminationStatus,
                                        stderr: errStr)
        }

        let zipData = try Data(contentsOf: tempZip)
        guard !zipData.isEmpty else { throw BackupError.noBytes }

        let payload: Data
        let outputURL: URL
        if let key {
            let sealed = try Crypto.encrypt(zipData, using: key)
            // Reuse the project-wide PIRC magic so a future "Restore
            // backup" path can detect format identically to settings/seen/etc.
            var bytes = Data(EncryptedJSON.magic)
            bytes.append(sealed)
            payload = bytes
            outputURL = backupDir.appendingPathComponent("PurpleIRC-\(stamp).zip.enc")
        } else {
            payload = zipData
            outputURL = backupDir.appendingPathComponent("PurpleIRC-\(stamp).zip")
        }
        try payload.write(to: outputURL, options: .atomic)
        return outputURL
    }

    /// Remove backup files older than the retention window. Only deletes
    /// files whose name starts with `PurpleIRC-` so unrelated files in
    /// the backup directory are never touched. Returns the count of
    /// files removed for telemetry / Setup UI feedback.
    @discardableResult
    static func trimOldBackups(in backupDir: URL,
                               retentionDays: Int) -> Int {
        guard retentionDays > 0 else { return 0 }
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86_400)
        guard let contents = try? fm.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return 0 }
        var removed = 0
        for url in contents {
            guard url.lastPathComponent.hasPrefix("PurpleIRC-"),
                  url.pathExtension == "enc" || url.pathExtension == "zip"
            else { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantFuture
            if modified < cutoff {
                if (try? fm.removeItem(at: url)) != nil {
                    removed += 1
                }
            }
        }
        return removed
    }

    /// List existing backups newest-first. Used by the Setup tab to show
    /// "5 backups, most recent: 2 hours ago". Tuple keeps the shape
    /// minimal — file URL + modification date are all the UI needs.
    static func listBackups(in backupDir: URL) -> [(url: URL, modified: Date)] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }
        var rows: [(URL, Date)] = []
        for url in contents
        where url.lastPathComponent.hasPrefix("PurpleIRC-")
              && (url.pathExtension == "enc" || url.pathExtension == "zip") {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            rows.append((url, modified))
        }
        return rows.sorted { $0.1 > $1.1 }
    }

    private static func timestampString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }
}

// MARK: - Factory reset

/// Wipes PurpleIRC's entire support directory. Used by the Setup →
/// Security "Factory Reset" button (after typed confirmation) and as a
/// recovery tool for incidents where the on-disk state has gotten out
/// of sync with the user's keystore. Doesn't touch the backup
/// directory — that's the user's escape hatch.
enum FactoryReset {
    /// Remove everything inside the support directory. Safe-by-default:
    /// refuses to operate on a directory that doesn't end in `PurpleIRC`
    /// to keep an accidental config-pointer from wiping `~/Library`.
    /// Returns the count of files removed.
    @discardableResult
    static func wipe(supportDir: URL) throws -> Int {
        guard supportDir.lastPathComponent == "PurpleIRC" else {
            // Refuse — caller passed something unexpected.
            return 0
        }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: supportDir, includingPropertiesForKeys: nil) else { return 0 }
        var removed = 0
        for url in contents {
            try fm.removeItem(at: url)
            removed += 1
        }
        return removed
    }
}
