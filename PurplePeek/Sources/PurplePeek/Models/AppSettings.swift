import Foundation

/// User preferences, persisted by `SettingsStore` as JSON in UserDefaults. Every field has
/// a sensible default so a fresh install is fully functional with no setup.
/// A remote root's local sidebar placement (see `AppSettings.remoteRootOrg`).
struct RemoteRootOrg: Codable, Equatable {
    var sectionId: String?
    var sortOrder: Int
}

struct AppSettings: Codable, Equatable {
    // General
    var defaultMode: AppMode = .folderBrowse
    var appearance: AppAppearance = .system
    var themeName: String = AppTheme.defaultThemeName   // "Purple Dusk"

    // Output locations (empty string ⇒ use the computed default under ~/Downloads/PurplePeek)
    var keptAudioExportPath: String = ""

    /// Name of a folder to skip when it sits directly under the scan root (and only there).
    /// Default "originals" — its whole subtree is ignored, but same-named folders nested
    /// deeper are still scanned. Empty ⇒ exclude nothing.
    var topLevelExcludeName: String = "originals"

    /// Watch the selected scan root with FSEvents and auto-rescan when files change on disk.
    /// Off by default — a refresh is otherwise on-demand (toolbar button / ⌘R).
    var autoRescanEnabled: Bool = false

    /// Detect exact (byte-identical) duplicates after a scan and collapse each set to one item,
    /// so a duplicate is decided once and imports once. On by default.
    var dedupeEnabled: Bool = true

    // Scan-root cleanup
    var scanRootAutoCleanupEnabled: Bool = false
    var scanRootAutoCleanupDays: Int = 180

    // PeekServer remote mode. When enabled + a host is set, PurplePeek acts as a LAN client of a
    // PeekServer instance (all roots/items/decisions come from it) instead of local folders. The
    // password is NOT here — it lives in the Keychain (see KeychainStore), keyed by user@host:port.
    var peekServerEnabled: Bool = false
    var peekServerHost: String = ""
    var peekServerPort: Int = 8788
    var peekServerUser: String = ""
    /// Local sidebar organization overlay for REMOTE roots (server roots carry no section/order of
    /// their own). Keyed by root path → its assigned section + within-group order. Applied after
    /// each remote fetch; ignored in local mode (local roots store this in the DB).
    var remoteRootOrg: [String: RemoteRootOrg] = [:]

    // Backup (PhantomLives auto-backup-on-launch standard)
    var autoBackupEnabled: Bool = true
    var backupPath: String = ""                         // empty ⇒ ~/Downloads/PurplePeek backup
    var backupRetentionDays: Int = 14
    var lastBackupAt: String? = nil

    init() {}

    /// Tolerant decoder: every field falls back to its default when absent from the saved JSON.
    /// Swift's synthesized decoder throws on ANY missing key (even with a default), which would
    /// reset ALL settings whenever a new field is added — that silently dropped the PeekServer
    /// connection when `remoteRootOrg` was introduced. `decodeIfPresent ?? default` makes settings
    /// forward/backward-compatible so adding fields never wipes existing ones.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? def }
        defaultMode = v(.defaultMode, .folderBrowse)
        appearance = v(.appearance, .system)
        themeName = v(.themeName, AppTheme.defaultThemeName)
        keptAudioExportPath = v(.keptAudioExportPath, "")
        topLevelExcludeName = v(.topLevelExcludeName, "originals")
        autoRescanEnabled = v(.autoRescanEnabled, false)
        dedupeEnabled = v(.dedupeEnabled, true)
        scanRootAutoCleanupEnabled = v(.scanRootAutoCleanupEnabled, false)
        scanRootAutoCleanupDays = v(.scanRootAutoCleanupDays, 180)
        peekServerEnabled = v(.peekServerEnabled, false)
        peekServerHost = v(.peekServerHost, "")
        peekServerPort = v(.peekServerPort, 8788)
        peekServerUser = v(.peekServerUser, "")
        remoteRootOrg = v(.remoteRootOrg, [:])
        autoBackupEnabled = v(.autoBackupEnabled, true)
        backupPath = v(.backupPath, "")
        backupRetentionDays = v(.backupRetentionDays, 14)
        lastBackupAt = (try? c.decodeIfPresent(String.self, forKey: .lastBackupAt)) ?? nil
    }
}
