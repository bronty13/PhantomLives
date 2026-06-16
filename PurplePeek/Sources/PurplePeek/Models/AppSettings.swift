import Foundation

/// User preferences, persisted by `SettingsStore` as JSON in UserDefaults. Every field has
/// a sensible default so a fresh install is fully functional with no setup.
struct AppSettings: Codable, Equatable {
    // General
    var defaultMode: AppMode = .folderBrowse
    var appearance: AppAppearance = .system
    var themeName: String = AppTheme.defaultThemeName   // "Purple Dusk"

    // Output locations (empty string ⇒ use the computed default under ~/Downloads/PurplePeek)
    var keptAudioExportPath: String = ""

    // Scan-root cleanup
    var scanRootAutoCleanupEnabled: Bool = false
    var scanRootAutoCleanupDays: Int = 180

    // Backup (PhantomLives auto-backup-on-launch standard)
    var autoBackupEnabled: Bool = true
    var backupPath: String = ""                         // empty ⇒ ~/Downloads/PurplePeek backup
    var backupRetentionDays: Int = 14
    var lastBackupAt: String? = nil

    init() {}
}
