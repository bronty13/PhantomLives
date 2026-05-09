import Foundation
import PurpleDedupCore

/// PhantomLives convention: every app that owns persistent user data runs an
/// automatic backup on launch. This is the app-side glue between `BackupService`
/// (Core, no settings dependency) and `SettingsStore` (App, owns the user prefs).
@MainActor
enum BackupRunner {

    /// Run a backup if it's enabled in settings AND we haven't run one in the
    /// debounce window. Errors are swallowed (logged via NSLog) — the app must
    /// never refuse to launch because backup failed.
    static func runOnLaunchIfDue(settingsStore: SettingsStore) {
        guard settingsStore.settings.autoBackupEnabled else { return }
        if let last = parseISO(settingsStore.settings.lastBackupAt),
           Date().timeIntervalSince(last) < BackupService.debounceSeconds {
            return
        }

        do {
            let supportDir = PurpleDedup.supportDirectoryURL
            try FileManager.default.createDirectory(
                at: supportDir, withIntermediateDirectories: true
            )
            let url = try BackupService.runBackup(
                supportDir: supportDir,
                backupDir: settingsStore.resolvedBackupPath
            )
            _ = BackupService.trimOldBackups(
                in: settingsStore.resolvedBackupPath,
                retentionDays: settingsStore.settings.backupRetentionDays
            )
            settingsStore.settings.lastBackupAt = isoNow()
            NSLog("PurpleDedup: backup-on-launch wrote \(url.lastPathComponent)")
        } catch {
            NSLog("PurpleDedup: backup-on-launch failed — \(error.localizedDescription)")
        }
    }

    private static func isoNow() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: Date())
    }

    private static func parseISO(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: s)
    }
}
