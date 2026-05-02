import Foundation

struct BackupService {
    static func runIfEnabled(settings: AppSettings, backupURL: URL) {
        guard settings.autoBackupEnabled else { return }
        Task.detached(priority: .background) {
            do {
                try await performBackup(to: backupURL)
                try trimOldBackups(in: backupURL, retentionDays: settings.backupRetentionDays)
            } catch {
                // Backup failure is silent — never block app launch
            }
        }
    }

    static func performBackup(to backupDir: URL) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let sourceDir = support.appendingPathComponent("WeightTracker")

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = fmt.string(from: Date())
        let zipName = "WeightTracker-\(timestamp).zip"
        let tempZip = fm.temporaryDirectory.appendingPathComponent("wt-backup-\(UUID().uuidString).zip")
        let destZip = backupDir.appendingPathComponent(zipName)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-rqX", tempZip.path, ".", "-x", "*.DS_Store"]
        process.currentDirectoryURL = sourceDir

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "BackupService", code: Int(process.terminationStatus))
        }

        try fm.moveItem(at: tempZip, to: destZip)
    }

    static func trimOldBackups(in dir: URL, retentionDays: Int) throws {
        let fm = FileManager.default
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        let items = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd-HHmmss"

        for item in items {
            guard item.lastPathComponent.hasPrefix("WeightTracker-"),
                  item.pathExtension == "zip" else { continue }
            let nameWithoutExt = item.deletingPathExtension().lastPathComponent
            let timestampStr = String(nameWithoutExt.dropFirst("WeightTracker-".count))
            guard let fileDate = fmt.date(from: timestampStr) else { continue }
            if fileDate < cutoff {
                try? fm.removeItem(at: item)
            }
        }
    }
}
