import Foundation
import SwiftUI
import PurpleDedupCore

/// PhantomLives convention-compliant settings store. Mirrors `Timeliner`'s shape so
/// the BackupService launch-on-launch logic plugs in identically.
///
/// Values persist to `UserDefaults` under the `PurpleDedup.` prefix so a future
/// settings reset just blows away keys with that prefix.
@MainActor
final class SettingsStore: ObservableObject {

    @Published var settings: AppSettings {
        didSet { save() }
    }

    init() {
        self.settings = Self.load()
    }

    /// One-line resolved backup directory. Falls back to the default if the user's
    /// pick is empty/unset.
    var resolvedBackupPath: URL {
        if let s = settings.backupPath, !s.isEmpty {
            return URL(fileURLWithPath: (s as NSString).expandingTildeInPath)
        }
        return PurpleDedup.defaultBackupDirectoryURL
    }

    func save() {
        let d = UserDefaults.standard
        d.set(settings.autoBackupEnabled, forKey: Self.key("autoBackupEnabled"))
        d.set(settings.backupPath, forKey: Self.key("backupPath"))
        d.set(settings.backupRetentionDays, forKey: Self.key("backupRetentionDays"))
        d.set(settings.lastBackupAt, forKey: Self.key("lastBackupAt"))
        d.set(settings.useCachedEngine, forKey: Self.key("useCachedEngine"))
        d.set(settings.ffmpegFallbackEnabled, forKey: Self.key("ffmpegFallbackEnabled"))
        d.set(settings.lastSourcePaths, forKey: Self.key("lastSourcePaths"))
        d.set(settings.photoThreshold, forKey: Self.key("photoThreshold"))
        d.set(settings.videoThreshold, forKey: Self.key("videoThreshold"))
        d.set(settings.includeSimilarPhotos, forKey: Self.key("includeSimilarPhotos"))
        d.set(settings.includeSimilarVideos, forKey: Self.key("includeSimilarVideos"))
        d.set(settings.selectionRuleNames, forKey: Self.key("selectionRuleNames"))
        d.set(settings.folderPriority, forKey: Self.key("folderPriority"))
        d.set(settings.stageFolderPath, forKey: Self.key("stageFolderPath"))
        // Encode the filter map as JSON — UserDefaults can't store
        // `PhotoLibraryFilter` directly. Empty map writes nil, so a future
        // load reads back an empty dict cleanly.
        if settings.photoLibraryFilters.isEmpty {
            d.removeObject(forKey: Self.key("photoLibraryFilters"))
        } else if let data = try? JSONEncoder().encode(settings.photoLibraryFilters) {
            d.set(data, forKey: Self.key("photoLibraryFilters"))
        }
    }

    static func load() -> AppSettings {
        let d = UserDefaults.standard
        var s = AppSettings()
        if d.object(forKey: key("autoBackupEnabled")) != nil {
            s.autoBackupEnabled = d.bool(forKey: key("autoBackupEnabled"))
        }
        s.backupPath = d.string(forKey: key("backupPath"))
        if d.object(forKey: key("backupRetentionDays")) != nil {
            s.backupRetentionDays = d.integer(forKey: key("backupRetentionDays"))
        }
        s.lastBackupAt = d.string(forKey: key("lastBackupAt"))
        if d.object(forKey: key("useCachedEngine")) != nil {
            s.useCachedEngine = d.bool(forKey: key("useCachedEngine"))
        }
        if d.object(forKey: key("ffmpegFallbackEnabled")) != nil {
            s.ffmpegFallbackEnabled = d.bool(forKey: key("ffmpegFallbackEnabled"))
        }
        s.lastSourcePaths = (d.array(forKey: key("lastSourcePaths")) as? [String]) ?? []
        if d.object(forKey: key("photoThreshold")) != nil {
            s.photoThreshold = d.integer(forKey: key("photoThreshold"))
        }
        if d.object(forKey: key("videoThreshold")) != nil {
            s.videoThreshold = d.integer(forKey: key("videoThreshold"))
        }
        if d.object(forKey: key("includeSimilarPhotos")) != nil {
            s.includeSimilarPhotos = d.bool(forKey: key("includeSimilarPhotos"))
        }
        if d.object(forKey: key("includeSimilarVideos")) != nil {
            s.includeSimilarVideos = d.bool(forKey: key("includeSimilarVideos"))
        }
        if let names = d.array(forKey: key("selectionRuleNames")) as? [String], !names.isEmpty {
            s.selectionRuleNames = names
        }
        s.folderPriority = (d.array(forKey: key("folderPriority")) as? [String]) ?? []
        s.stageFolderPath = d.string(forKey: key("stageFolderPath"))
        if let data = d.data(forKey: key("photoLibraryFilters")),
           let decoded = try? JSONDecoder().decode([String: PhotoLibraryFilter].self, from: data) {
            s.photoLibraryFilters = decoded
        }
        return s
    }

    private static func key(_ k: String) -> String { "PurpleDedup.\(k)" }
}

struct AppSettings: Equatable {
    var autoBackupEnabled: Bool = true
    var backupPath: String?
    var backupRetentionDays: Int = 14
    /// ISO-formatted timestamp of the most recent successful backup. Used by the
    /// debounce check in `BackupService.runOnLaunchIfDue`.
    var lastBackupAt: String?
    /// When true (default), the GUI uses `CachedScanEngine` so second scans skip
    /// re-hashing unchanged files. The plain `ScanEngine` is kept as an opt-out for
    /// debugging — toggle it off if cached results look stale during development.
    var useCachedEngine: Bool = true

    /// When true, the engine falls back to a system-installed `ffmpeg` to
    /// fingerprint videos AVFoundation can't decode (MKV, AVI, WMV, WebM).
    /// Default false — the user has to install FFmpeg themselves (Homebrew /
    /// MacPorts) and explicitly opt in. When ffmpeg isn't found at scan time,
    /// the toggle is silently a no-op.
    var ffmpegFallbackEnabled: Bool = false

    /// Persisted across app launches so the user doesn't reconfigure every time.
    /// Restored on first appearance of the main window; the user can re-scan with
    /// one click (the cache makes it fast for unchanged files).
    var lastSourcePaths: [String] = []
    var photoThreshold: Int = 6
    var videoThreshold: Int = 6
    var includeSimilarPhotos: Bool = true
    var includeSimilarVideos: Bool = true

    /// Smart-select rule chain — ordered list of rule raw values. Stored as
    /// strings rather than the `Rule` enum so future rule additions don't
    /// invalidate persisted preferences (unknown values are filtered out at
    /// load time). Default chain matches `RuleChain.default` plus folder
    /// priority disabled (empty list = rule has no opinion = falls through).
    var selectionRuleNames: [String] = [
        "highestResolution",
        "mostMetadata",
        "newestCaptureDate",
        "shortestPath",
    ]

    /// Ordered folder paths used by the `folderPriority` rule. Earlier =
    /// preferred. Empty list means the rule has no opinion (it falls
    /// through to the next rule in the chain).
    var folderPriority: [String] = []

    /// FR-5.5: instead of moving DELETE-marked files to the Finder Trash,
    /// move them to this folder. nil/empty = use Trash (default). Useful
    /// for users who want to stage duplicates for review before committing
    /// — drop everything in `~/Downloads/Dedupe Stage`, glance through it
    /// in Finder, then `rm -rf` (or move to Trash from there) when satisfied.
    var stageFolderPath: String?

    /// Per-Photos-library scan filters, keyed by absolute path string. When
    /// a `.photoslibrary` source has an entry here, the scan only walks the
    /// matching basenames (resolved via PhotoKit at scan time). Filters
    /// without a matching source are left in place — they reactivate if the
    /// user re-adds the same library.
    var photoLibraryFilters: [String: PhotoLibraryFilter] = [:]
}
