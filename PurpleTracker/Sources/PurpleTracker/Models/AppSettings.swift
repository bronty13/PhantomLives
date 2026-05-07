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

    // File-store templates (`{year}` and `{title}` are the only substitutions)
    var fileStorePrimaryTemplate: String =
        "~/Library/CloudStorage/OneDrive-defiSOLUTIONS/{year}/{date} {title}"
    var fileStoreSecondaryTemplate: String =
        "~/Downloads/PurpleTracker/{title}"

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
              var decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else { return }
        // One-shot migration: bump the legacy secondary-store default
        // (`~/Downloads/{title}`) to the new default (`~/Downloads/PurpleTracker/{title}`).
        // Only touches users who never customised it.
        if decoded.fileStoreSecondaryTemplate == "~/Downloads/{title}" {
            decoded.fileStoreSecondaryTemplate = "~/Downloads/PurpleTracker/{title}"
        }
        settings = decoded
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    var resolvedBackupPath: URL {
        if settings.backupPath.isEmpty {
            return Self.downloadsDir.appendingPathComponent("PurpleTracker backup", isDirectory: true)
        }
        return URL(fileURLWithPath: (settings.backupPath as NSString).expandingTildeInPath)
    }

    var resolvedExportDirectory: URL {
        if settings.defaultExportDirectory.isEmpty {
            return Self.downloadsDir.appendingPathComponent("PurpleTracker", isDirectory: true)
        }
        return URL(fileURLWithPath: (settings.defaultExportDirectory as NSString).expandingTildeInPath)
    }

    private static var downloadsDir: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }
}
