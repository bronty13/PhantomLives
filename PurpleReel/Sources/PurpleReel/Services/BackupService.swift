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
}
