import Foundation

/// Auto-backup service for PurpleSpeak.
///
/// PhantomLives convention (`docs/auto-backup-on-launch.md`): every app that
/// owns persistent user data runs an automatic backup on launch. Default
/// location `~/Downloads/PurpleSpeak backup/`, 14-day retention, debounced to
/// 5 minutes, and it never throws out of the launch path.
@MainActor
enum BackupService {

    static let debounceSeconds: TimeInterval = 5 * 60
    static let archivePrefix = "PurpleSpeak-"

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
    /// logged via NSLog and swallowed — launch must never fail on backup.
    static func runOnLaunchIfDue(settingsStore: SettingsStore) {
        guard settingsStore.settings.autoBackupEnabled else { return }
        if let last = parseISO(settingsStore.settings.lastBackupAt),
           Date().timeIntervalSince(last) < debounceSeconds {
            return
        }
        do {
            let url = try doBackup(settingsStore: settingsStore)
            NSLog("PurpleSpeak: backup-on-launch wrote \(url.lastPathComponent)")
        } catch {
            NSLog("PurpleSpeak: backup-on-launch failed — \(error.localizedDescription)")
        }
    }

    @discardableResult
    static func doBackup(settingsStore: SettingsStore) throws -> URL {
        let url = try runBackup(supportDir: SupportPaths.supportDirectory,
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
        let tempZip = fm.temporaryDirectory
            .appendingPathComponent("purplespeak-backup-\(UUID().uuidString).zip")
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
        case invalidArchive
        var errorDescription: String? {
            switch self {
            case .unzipFailed(let s): return "Couldn't unzip backup: \(s)"
            case .invalidArchive:     return "Backup didn't contain a PurpleSpeak library."
            }
        }
    }

    struct VerifyResult {
        let archiveURL: URL
        let archiveSize: Int
        let fileCount: Int
        let documentCount: Int
        let entries: [String]
    }

    /// Non-destructive: extract to a temp dir, confirm it holds a library, and
    /// report a summary the UI shows before a real restore.
    static func verifyArchive(at archiveURL: URL) throws -> VerifyResult {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("ps-verify-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        try unzip(archiveURL: archiveURL, to: staging)

        var fileCount = 0
        var entries: [String] = []
        if let en = fm.enumerator(at: staging, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let url as URL in en {
                if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                    fileCount += 1
                    if entries.count < 25 {
                        entries.append(url.path.replacingOccurrences(of: staging.path + "/", with: ""))
                    }
                }
            }
        }
        var documentCount = 0
        let libURL = staging.appendingPathComponent("library.json")
        if let data = try? Data(contentsOf: libURL),
           let docs = try? JSONDecoder().decode([Document].self, from: data) {
            documentCount = docs.count
        } else if !fm.fileExists(atPath: staging.appendingPathComponent("settings.json").path) {
            throw RestoreError.invalidArchive
        }
        let size = (try? fm.attributesOfItem(atPath: archiveURL.path)[.size] as? Int) ?? 0
        return VerifyResult(archiveURL: archiveURL, archiveSize: size,
                            fileCount: fileCount, documentCount: documentCount,
                            entries: entries.sorted())
    }

    /// Destructive: replace the support directory contents with the archive.
    static func restoreArchive(at archiveURL: URL) throws {
        let fm = FileManager.default
        _ = try verifyArchive(at: archiveURL)   // throws on garbage
        let supportDir = SupportPaths.supportDirectory
        let staging = fm.temporaryDirectory
            .appendingPathComponent("ps-restore-\(UUID().uuidString)", isDirectory: true)
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
        let errPipe = Pipe()
        proc.standardError = errPipe
        do { try proc.run() } catch { throw RestoreError.unzipFailed(error.localizedDescription) }
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            throw RestoreError.unzipFailed("exit \(proc.terminationStatus): \(err)")
        }
    }

    // MARK: - Helpers

    private static func timestamp() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"; return f.string(from: Date())
    }
    private static func isoNow() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f.string(from: Date())
    }
    private static func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f.date(from: s)
    }
}
