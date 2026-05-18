import Foundation

/// Auto-backup-on-launch per PhantomLives convention. Zips the entire
/// `~/Library/Application Support/PurpleReel/` directory into
/// `~/Downloads/PurpleReel backup/` on launch, debouncing if a backup
/// was made in the last 5 minutes, and trimming archives older than
/// the retention window.
///
/// Reference impl: Timeliner/Services/BackupService.swift
enum BackupService {
    static let appName = "PurpleReel"
    static let debounce: TimeInterval = 5 * 60
    static let defaultRetentionDays: Int = 14

    static func runOnLaunchIfNeeded() {
        guard UserDefaults.standard.object(forKey: "autoBackupEnabled") as? Bool ?? true else { return }
        let last = UserDefaults.standard.double(forKey: "lastBackupAt")
        if last > 0, Date().timeIntervalSince1970 - last < debounce {
            return
        }
        DispatchQueue.global(qos: .utility).async {
            do {
                try runBackup()
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastBackupAt")
                try trimOld()
            } catch {
                NSLog("[PurpleReel] backup failed: \(error)")
            }
        }
    }

    static func runBackup() throws {
        let fm = FileManager.default
        let src = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                              appropriateFor: nil, create: true)
            .appendingPathComponent(appName, isDirectory: true)
        guard fm.fileExists(atPath: src.path) else { return }

        let backupDir = try backupDirectory()
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let stamp = Self.timestamp()
        let dst = backupDir.appendingPathComponent("\(appName)-\(stamp).zip")

        // Use /usr/bin/ditto for a fast, atomic zip. Sandbox is off,
        // so this is fine.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", src.path, dst.path]
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            throw NSError(domain: "PurpleReel.Backup", code: Int(task.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "ditto exited \(task.terminationStatus)"])
        }
    }

    static func backupDirectory() throws -> URL {
        if let override = UserDefaults.standard.string(forKey: "backupPath") {
            return URL(fileURLWithPath: override)
        }
        let downloads = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
        return downloads.appendingPathComponent("\(appName) backup", isDirectory: true)
    }

    static func trimOld() throws {
        let retentionDays = UserDefaults.standard.object(forKey: "backupRetentionDays") as? Int ?? defaultRetentionDays
        guard retentionDays > 0 else { return }
        let dir = try backupDirectory()
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
        for f in files where f.lastPathComponent.hasPrefix("\(appName)-") && f.pathExtension == "zip" {
            let mod = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            if mod < cutoff {
                try? fm.removeItem(at: f)
            }
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }

    // MARK: - List / verify / restore (Settings → Backup actions)

    /// Newest-first list of `<AppName>-*.zip` archives in the backup
    /// directory. Tolerant of an empty/non-existent dir.
    static func listBackups() throws -> [URL] {
        let dir = try backupDirectory()
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        )
        let ours = files.filter {
            $0.lastPathComponent.hasPrefix("\(appName)-") &&
            $0.pathExtension.lowercased() == "zip"
        }
        return ours.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate) ?? .distantPast
            return l > r
        }
    }

    /// Non-destructive check: unzip into a tempdir and confirm the
    /// expected payload (Application Support/<AppName>/) is present
    /// plus a SQLite file inside.
    static func verify(archive url: URL) throws -> (ok: Bool, summary: String) {
        let tmp = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("PurpleReel-verify-\(UUID().uuidString)")
        try? FileManager.default.removeItem(atPath: tmp)
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-x", "-k", url.path, tmp]
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            return (false, "ditto extraction failed (\(task.terminationStatus))")
        }
        // Look for the payload.
        let payload = URL(fileURLWithPath: tmp).appendingPathComponent(appName)
        let dbPath = payload.appendingPathComponent("purplereel.sqlite").path
        let dbExists = FileManager.default.fileExists(atPath: dbPath)
        let size = (try? FileManager.default.attributesOfItem(atPath: dbPath)[.size] as? Int64) ?? 0
        return (
            dbExists,
            dbExists
                ? "✓ DB present (\(ByteCountFormatter().string(fromByteCount: size)))"
                : "✗ DB missing in archive"
        )
    }

    /// Restore: create a safety zip of the current state first, then
    /// replace the Application Support directory atomically.
    static func restore(from archive: URL) throws {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent(appName, isDirectory: true)

        // Safety backup first — write a `<AppName>-pre-restore-…zip`
        // alongside the archive being restored. If restore goes
        // sideways the user can roll forward from this.
        let backupDir = try backupDirectory()
        let safety = backupDir.appendingPathComponent(
            "\(appName)-pre-restore-\(timestamp()).zip"
        )
        if fm.fileExists(atPath: appSupport.path) {
            let zipTask = Process()
            zipTask.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            zipTask.arguments = ["-c", "-k", "--sequesterRsrc",
                                  "--keepParent", appSupport.path, safety.path]
            try zipTask.run()
            zipTask.waitUntilExit()
        }

        // Wipe live state.
        if fm.fileExists(atPath: appSupport.path) {
            try fm.removeItem(at: appSupport)
        }
        try fm.createDirectory(at: appSupport.deletingLastPathComponent(),
                                 withIntermediateDirectories: true)

        // Unzip the archive into Application Support's parent so the
        // contained `<AppName>/` folder lands at the right place.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-x", "-k", archive.path,
                            appSupport.deletingLastPathComponent().path]
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            throw NSError(domain: "PurpleReel.Restore",
                           code: Int(task.terminationStatus),
                           userInfo: [NSLocalizedDescriptionKey:
                            "ditto exited \(task.terminationStatus)"])
        }
    }

    static var lastBackupDate: Date? {
        let ts = UserDefaults.standard.double(forKey: "lastBackupAt")
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }
}
