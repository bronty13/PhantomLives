import Foundation
import SwiftUI
import ArchiveKit

/// App-wide settings, persisted as JSON in Application Support. Kept tiny and
/// Codable so the launch-time backup (which zips Application Support) captures
/// it, and so the Settings UI binds directly.
struct AppSettings: Codable, Equatable {
    // Backup (PhantomLives auto-backup standard)
    var autoBackupEnabled: Bool = true
    var backupRetentionDays: Int = 14
    var lastBackupAt: String? = nil
    var customBackupPath: String? = nil

    // Extraction / creation defaults
    var defaultExtractPath: String? = nil          // nil → ~/Downloads/PurpleArchive
    var defaultFormatRaw: String = ArchiveFormat.tarZst.rawValue
    var defaultLevel: Int = 6
    var stripMacMetadata: Bool = true

    // Appearance
    var accentColorName: String = "purple"
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings { didSet { scheduleSave() } }

    static let appName = "PurpleArchive"

    /// `~/Library/Application Support/PurpleArchive/` — internal data home.
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var fileURL: URL { Self.supportDirectory.appendingPathComponent("settings.json") }
    private var saveWork: DispatchWorkItem?

    init() {
        let url = Self.supportDirectory.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
            // Materialize defaults on first run so (a) settings persist even if
            // the user never changes anything and (b) the support dir is never
            // empty — an empty dir makes `zip` exit "nothing to do" and the
            // launch backup would silently never produce a file.
            save()
        }
    }

    /// `~/Downloads/PurpleArchive backup/` unless the user overrides it.
    var resolvedBackupPath: URL {
        if let custom = settings.customBackupPath, !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/\(Self.appName) backup", isDirectory: true)
    }

    /// `~/Downloads/PurpleArchive/` unless overridden — the default extract root.
    var resolvedExtractRoot: URL {
        if let custom = settings.defaultExtractPath, !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/\(Self.appName)", isDirectory: true)
    }

    var defaultFormat: ArchiveFormat {
        ArchiveFormat(rawValue: settings.defaultFormatRaw) ?? .tarZst
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
