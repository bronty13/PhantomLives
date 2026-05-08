import Foundation

/// Auto-backup service for messages-exporter-gui.
///
/// PhantomLives convention (`PhantomLives/CLAUDE.md`): every app that
/// owns persistent user data must run an automatic backup on launch.
/// Default location: `~/Downloads/MessagesExporterGUI backup/`. Default
/// retention: 14 days. Skipped if the last successful backup is under 5
/// minutes old (debounce). Failures are logged via `NSLog`, never thrown
/// — the app must launch even if backup fails.
///
/// Modeled on `Timeliner/Sources/Timeliner/Services/BackupService.swift`.
/// We don't ship a SQLite database (run history + presets are JSON), so
/// the verify path counts JSON file entries rather than DB rows.
@MainActor
enum BackupService {

    /// Skip auto-backup if the last successful run is less than this many
    /// seconds old. Prevents repeated relaunches during a debugging session
    /// from filling the backup folder.
    static let debounceSeconds: TimeInterval = 5 * 60

    /// Filename prefix recognised by the retention trim and the listing
    /// UI. Archive name format is `MessagesExporterGUI-yyyy-MM-dd-HHmmss.zip`.
    static let archivePrefix = "MessagesExporterGUI-"

    enum BackupKeys {
        static let enabled       = "autoBackupEnabled"
        static let path          = "backupPath"
        static let retentionDays = "backupRetentionDays"
        static let lastBackupAt  = "lastBackupAt"
    }

    static let defaultRetentionDays = 14

    /// `~/Downloads/MessagesExporterGUI backup/` (sibling of the regular
    /// output dir, with a trailing " backup"). Created on demand.
    static var defaultBackupDir: URL {
        let downloads = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads")
        return downloads.appendingPathComponent("MessagesExporterGUI backup",
                                                isDirectory: true)
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

    /// Run a backup if it's enabled AND the debounce window has elapsed.
    /// Errors are swallowed (logged via NSLog) — never throw out of this.
    /// Public entry point used from `MessagesExporterGUIApp.init`.
    static func runOnLaunchIfDue() {
        let defaults = UserDefaults.standard
        let enabledKey = BackupKeys.enabled
        // Default-on per CLAUDE.md spec. We register the default so a
        // fresh install doesn't read `false` because the key is unset.
        defaults.register(defaults: [enabledKey: true,
                                     BackupKeys.retentionDays: defaultRetentionDays])
        guard defaults.bool(forKey: enabledKey) else { return }
        if let last = parseISO(defaults.string(forKey: BackupKeys.lastBackupAt) ?? ""),
           Date().timeIntervalSince(last) < debounceSeconds {
            return
        }
        do {
            let url = try doBackup()
            NSLog("MessagesExporterGUI: backup-on-launch wrote \(url.lastPathComponent)")
        } catch {
            NSLog("MessagesExporterGUI: backup-on-launch failed — \(error.localizedDescription)")
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
            .appendingPathComponent("medexp-backup-\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: tempZip) }

        // Empty support dir is fine — we still want to write a marker zip
        // so retention sees a "we tried today" file and the user has a
        // baseline to restore against.
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

        // `zip -rqX .` against an empty directory exits 12 (nothing to do)
        // *unless* there's at least one file. If we somehow got here with
        // no zip on disk, write a minimal marker so the rest of the
        // pipeline works the same way.
        if !fm.fileExists(atPath: tempZip.path) {
            // Create an empty zip so the file exists and the verify step
            // can read it back. This is the "first launch, no data yet"
            // case — there's literally nothing to back up.
            try Data().write(to: tempZip)
        }

        let zipData = try Data(contentsOf: tempZip)
        // Empty data is OK on first launch (nothing to back up yet); we
        // still write the marker so the retention/listing UI is non-empty.

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

    /// Non-destructive: extract the archive, count JSON entries, return a
    /// summary the UI can show before the user commits to a real restore.
    static func verifyArchive(at archiveURL: URL) throws -> VerifyResult {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("medexp-verify-\(UUID().uuidString)", isDirectory: true)
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

        // Count rows in any runs.json / presets.json that's present. Both
        // are optional — a fresh install backs up an empty support dir.
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
           let rows = try? dec.decode([ExportPreset].self, from: data) {
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

    /// Destructive: replace the support directory contents with the
    /// unpacked archive. Pre-flights with `verifyArchive` so a garbage
    /// archive can't wipe live state.
    static func restoreArchive(at archiveURL: URL, into supportDir: URL = AppSupport.directory) throws {
        let fm = FileManager.default
        _ = try verifyArchive(at: archiveURL)

        let staging = fm.temporaryDirectory
            .appendingPathComponent("medexp-restore-\(UUID().uuidString)", isDirectory: true)
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
