import Foundation
import SwiftUI

/// All persisted user preferences. Lives at
/// `~/Library/Application Support/PurpleTracker/settings.json`. The DB owns
/// type / status pick-lists (so the user can edit them with the rest of the
/// data and they round-trip through backup zips); the `Settings` document
/// owns per-app behavior, defaults, and external-label customization.
struct AppSettings: Codable {
    // Backup (PhantomLives auto-backup-on-launch standard, 30-day default)
    var autoBackupEnabled: Bool = true
    var backupPath: String = ""             // empty → resolvedBackupPath default
    var backupRetentionDays: Int = 30
    var lastBackupAt: String = ""           // ISO-8601, empty if never

    // Export
    var defaultExportDirectory: String = "" // empty → resolvedExportDirectory default

    // External-reference display labels (configurable; defaults per spec)
    var external1Label: String = "defi SUPPORT (SNOW)"
    var external2Label: String = "Azure DevOps (ADO)"
    var external3Label: String = "Client Reference"

    // File-store templates (`{year}` and `{title}` are the only substitutions).
    // Secondary-store default lives under the per-app `~/Downloads/PurpleTracker/`
    // umbrella so we never sprinkle multiple folders into Downloads.
    var fileStorePrimaryTemplate: String =
        "~/Library/CloudStorage/OneDrive-defiSOLUTIONS/{year}/{date} {title}"
    var fileStoreSecondaryTemplate: String =
        "~/Downloads/PurpleTracker/Files/{title}"

    // Spell-check
    var autocorrectEnabled: Bool = false    // continuous spellcheck always on; correction off by default

    // Active-timer persistence (so a relaunch can offer to resume)
    var activeTimerMatterId: String = ""
    var activeTimerStartedAt: String = ""   // ISO-8601

    // People auto-import — when on, the most recent
    // `~/Downloads/ADP_IMP_UserFeed_*.csv` is imported on launch if it
    // hasn't been imported before. Filename (not contents) is the dedupe key.
    var peopleAutoImportOnLaunchEnabled: Bool = true
    var lastImportedAdpFilename: String = ""
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings = AppSettings()

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL { self.fileURL = fileURL } else {
            let support = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = support.appendingPathComponent("PurpleTracker", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("settings.json")
        }
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              var decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            // No prior settings — still try the on-disk Downloads cleanup.
            Self.migrateLegacyDownloadsLayout()
            return
        }
        // One-shot template migrations. Only touch users who never customised
        // the field (string equality with the prior default).
        if decoded.fileStoreSecondaryTemplate == "~/Downloads/{title}" ||
           decoded.fileStoreSecondaryTemplate == "~/Downloads/PurpleTracker/{title}" {
            decoded.fileStoreSecondaryTemplate = "~/Downloads/PurpleTracker/Files/{title}"
        }
        // Old explicit backup path → new sub-folder default (clearing the
        // override lets `resolvedBackupPath` use the new computed default).
        let legacyBackup = Self.downloadsDir.appendingPathComponent("PurpleTracker backup", isDirectory: true).path
        let expandedBackup = (decoded.backupPath as NSString).expandingTildeInPath
        if expandedBackup == legacyBackup || decoded.backupPath == "~/Downloads/PurpleTracker backup" {
            decoded.backupPath = ""
        }
        settings = decoded
        // Physically migrate the legacy `~/Downloads/PurpleTracker backup` folder
        // into the new `~/Downloads/PurpleTracker/Backup` location.
        Self.migrateLegacyDownloadsLayout()
        save()
    }

    /// Move any legacy `~/Downloads/PurpleTracker backup/` zips into the new
    /// `~/Downloads/PurpleTracker/Backup/` sub-folder so there's only ever one
    /// PurpleTracker folder in Downloads. Idempotent and safe — only moves
    /// files when the destination doesn't already have a same-named entry.
    static func migrateLegacyDownloadsLayout() {
        let fm = FileManager.default
        let legacy = downloadsDir.appendingPathComponent("PurpleTracker backup", isDirectory: true)
        let newRoot = downloadsDir.appendingPathComponent("PurpleTracker", isDirectory: true)
        let newBackup = newRoot.appendingPathComponent("Backup", isDirectory: true)

        guard fm.fileExists(atPath: legacy.path) else { return }
        try? fm.createDirectory(at: newBackup, withIntermediateDirectories: true)
        if let kids = try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil) {
            for kid in kids {
                let dest = newBackup.appendingPathComponent(kid.lastPathComponent)
                if !fm.fileExists(atPath: dest.path) {
                    try? fm.moveItem(at: kid, to: dest)
                }
            }
        }
        // If the legacy folder is now empty, remove it. If anything was left
        // behind (e.g. duplicates), leave the folder for the user to inspect.
        if let remaining = try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil),
           remaining.isEmpty {
            try? fm.removeItem(at: legacy)
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    var resolvedBackupPath: URL {
        if settings.backupPath.isEmpty {
            // Single per-app folder under Downloads with a Backup sub-folder
            // — keeps Downloads tidy (no sibling "PurpleTracker backup").
            return Self.downloadsDir
                .appendingPathComponent("PurpleTracker", isDirectory: true)
                .appendingPathComponent("Backup", isDirectory: true)
        }
        return URL(fileURLWithPath: (settings.backupPath as NSString).expandingTildeInPath)
    }

    var resolvedExportDirectory: URL {
        if settings.defaultExportDirectory.isEmpty {
            // Same umbrella — exports live under PurpleTracker/Exports/.
            return Self.downloadsDir
                .appendingPathComponent("PurpleTracker", isDirectory: true)
                .appendingPathComponent("Exports", isDirectory: true)
        }
        return URL(fileURLWithPath: (settings.defaultExportDirectory as NSString).expandingTildeInPath)
    }

    static var downloadsDir: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }
}
