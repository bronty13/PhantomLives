import Foundation
import Combine
import PurpleAtticCore

/// App-level settings (backup config) — distinct from the `ArchiveProfile` (the job
/// description). Both persist under `~/Library/Application Support/PurpleAttic/`.
struct AppSettings: Codable {
    var autoBackupEnabled: Bool = true
    var backupRetentionDays: Int = 14
    var backupDirectoryOverride: String? = nil
    var lastBackupAt: String? = nil
    var schedule: ArchiveSchedule = ArchiveSchedule()

    init() {}

    // Decode each key with a default so older settings.json files (written before a field
    // existed) still load cleanly instead of resetting all settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoBackupEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoBackupEnabled) ?? true
        backupRetentionDays = try c.decodeIfPresent(Int.self, forKey: .backupRetentionDays) ?? 14
        backupDirectoryOverride = try c.decodeIfPresent(String.self, forKey: .backupDirectoryOverride)
        lastBackupAt = try c.decodeIfPresent(String.self, forKey: .lastBackupAt)
        schedule = try c.decodeIfPresent(ArchiveSchedule.self, forKey: .schedule) ?? ArchiveSchedule()
    }
}

/// Owns the persisted `AppSettings` and the single editable `ArchiveProfile`, exposing both
/// as `@Published` so the SwiftUI Settings views bind directly. Saving writes the profile
/// JSON (shared with the `pattic` CLI) and the settings JSON.
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings
    @Published var profile: ArchiveProfile

    private static func settingsURL() -> URL {
        ProfileStore.defaultDirectory().appendingPathComponent("settings.json")
    }

    init() {
        // Settings
        if let data = try? Data(contentsOf: SettingsStore.settingsURL()),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
        // Profile — load existing, else seed a sample so the UI has something to edit.
        let profileURL = ProfileStore.defaultProfileURL()
        if let loaded = try? ProfileStore.load(from: profileURL) {
            self.profile = loaded
        } else {
            self.profile = ProfileStore.sample()
            _ = try? ProfileStore.save(self.profile, to: profileURL)
        }
    }

    /// Persist both settings and profile. Cheap; called on explicit Save and after backups.
    func save() {
        let dir = ProfileStore.defaultDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(settings) {
            try? data.write(to: SettingsStore.settingsURL())
        }
        _ = try? ProfileStore.save(profile, to: ProfileStore.defaultProfileURL())
    }

    /// Default `~/Downloads/PurpleAttic backup/` unless overridden.
    var resolvedBackupPath: URL {
        if let override = settings.backupDirectoryOverride, !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/PurpleAttic backup", isDirectory: true)
    }
}
