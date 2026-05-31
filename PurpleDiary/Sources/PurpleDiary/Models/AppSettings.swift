import Foundation

/// Codable settings bundle persisted as `settings.json` in the support
/// directory. Defaults are chosen so a brand-new install is immediately
/// usable: auto-backup on, 14-day retention, lock off (opt-in), 750-word
/// daily goal.
struct AppSettings: Codable {
    // Appearance
    var accentColorHex: String = "#7C5CFF"     // purple — the PurpleDiary accent
    var colorScheme: String = "auto"           // "auto" | "light" | "dark"

    // Writing
    var dailyWordGoal: Int = 750               // 0 disables the goal indicator
    var weekStartsMonday: Bool = false

    // Backup (auto-runs at every launch by default — PhantomLives convention)
    var autoBackupEnabled: Bool = true
    var backupPath: String = ""                // empty → resolvedBackupPath default
    var backupRetentionDays: Int = 14
    var lastBackupAt: String = ""              // ISO-8601, empty if never

    // Export
    var defaultExportDirectory: String = ""    // empty → resolvedExportDirectory default

    // Lock (app-lock — opt-in; the passphrase hash + salt live in the Keychain,
    // never here). `lockEnabled` gates the lock screen; `lockOnLaunch` and
    // `lockTimeoutMinutes` tune when it re-engages.
    var lockEnabled: Bool = false
    var lockOnLaunch: Bool = true
    var requireBiometrics: Bool = true         // allow Touch ID to unlock
    var biometryOnlyMode: Bool = false         // Touch ID only, no password fallback

    // Sample data — one-shot flag so first launch seeds sample entries, but a
    // later delete isn't silently undone next launch.
    var sampleDataEverInstalled: Bool = false

    // IDs of entries created by the sample-data facility (first-launch seed +
    // bulk "Add 100"). Lets "Remove All Sample Entries" delete exactly what the
    // app generated without touching the user's own entries.
    var sampleDataIds: [String] = []
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings = AppSettings()

    private let fileURL: URL

    init() {
        let dir = AppSettings.supportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("settings.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else { return }
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
            return Self.downloadsDir.appendingPathComponent("PurpleDiary backup", isDirectory: true)
        }
        return URL(fileURLWithPath: settings.backupPath)
    }

    var resolvedExportDirectory: URL {
        if settings.defaultExportDirectory.isEmpty {
            return Self.downloadsDir.appendingPathComponent("PurpleDiary", isDirectory: true)
        }
        return URL(fileURLWithPath: settings.defaultExportDirectory)
    }

    private static var downloadsDir: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }
}

extension AppSettings {
    /// `~/Library/Application Support/PurpleDiary/`. Shared by the database,
    /// settings, and backup services so they all agree on one location.
    ///
    /// Under XCTest this routes to a fresh per-process temp directory instead of
    /// the user's real Application Support. Once `diary.sqlite` is
    /// SQLCipher-encrypted, a test that constructed the singleton (or a
    /// `KeyStore`) against the real support dir couldn't decrypt it (no key
    /// resolver at test time) and could disturb the user's real keystore — so
    /// every consumer agrees on an isolated, disposable path during tests.
    static var supportDirectory: URL {
        if isUnderXCTest { return testSupportDirectory }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("PurpleDiary", isDirectory: true)
    }

    private static let isUnderXCTest: Bool =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Per-process Application-Support stand-in used under XCTest. Created fresh
    /// on first read so each test process starts with a clean DB + no stale
    /// settings/keystore.
    private static let testSupportDirectory: URL = {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PurpleDiary-tests-\(ProcessInfo.processInfo.processIdentifier)",
                                    isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}
