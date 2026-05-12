import Foundation
import CryptoKit

/// Persisted to `~/Library/Application Support/PurpleLife/settings.json`.
/// Phase 1 only carried the four backup-related keys mandated by
/// `CLAUDE.md`; later phases extend this struct in place. The custom
/// `init(from:)` below uses `decodeIfPresent` for every key so older
/// settings.json files (missing whatever the latest phase added) decode
/// successfully — preserving existing user settings on upgrade rather
/// than silently resetting to defaults.
struct AppSettings: Codable {
    // Backup (auto-runs at every launch by default — PhantomLives convention).
    var autoBackupEnabled: Bool = true
    var backupPath: String = ""                // empty → resolvedBackupPath default
    var backupRetentionDays: Int = 14          // 0 means keep forever
    var lastBackupAt: String = ""              // ISO-8601, empty if never

    // Default user-visible output directory for exports etc.
    var defaultExportDirectory: String = ""    // empty → resolvedExportDirectory default

    // Today / Planner saved queries — Phase 3. Empty on first run; the
    // SettingsStore seeds the defaults from `SavedQuerySeed.allDefaults`
    // so the Today view has content out of the box.
    var todayQueries: [SavedQuery] = []
    var todayQueriesSeeded: Bool = false       // one-shot — re-adding a deleted default doesn't fight the user

    // Weight-type profile values — used by the Charts view kind's
    // future Goal-line overlay (slice 3b) and the Statistics panel
    // (BMI, days-to-goal, forecast). Optional Doubles so an unset
    // value doesn't render a misleading 0 on the chart. All in the
    // base unit (pounds / inches) — display units (kg, cm) are a UI
    // concern handled where shown.
    var goalWeightPounds: Double? = nil
    var startingWeightPounds: Double? = nil    // optional override; defaults to the first Weight record's value
    var heightInches: Double? = nil            // required for BMI
    var forecastDays: Int = 30                 // projection horizon for the forecast section

    // Appearance — Settings → Appearance tab. Local per-Mac preference;
    // not synced via CloudKit (different Macs may want different looks).
    // `themeID` resolves first against `PurpleTheme.allBuiltIns`, then
    // against `userThemes` (where the id is the UUID string).
    var themeID: String = "royalPurple"
    var appearance: AppearanceMode = .system
    /// User-built themes — `UserTheme` snapshots with light/dark hex
    /// slot pairs. Slice 1 ships persistence + resolution; slice 2 adds
    /// the WYSIWYG builder UI. Empty until the user creates one.
    var userThemes: [UserTheme] = []

    init() {}

    /// Lenient decoder: every key is read via `decodeIfPresent` so a
    /// settings.json from a pre-Phase-N build, missing keys added by
    /// later phases, still decodes — falling back to each property's
    /// declared default. Without this, the synthesized decoder throws
    /// on the first missing non-Optional key, `SettingsStore.load`'s
    /// `try?` swallows the error, and the user silently loses every
    /// previously-saved setting. Encoding uses Swift's synthesized
    /// `encode(to:)` so we always write the full current shape.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoBackupEnabled       = try c.decodeIfPresent(Bool.self,            forKey: .autoBackupEnabled)       ?? autoBackupEnabled
        backupPath              = try c.decodeIfPresent(String.self,          forKey: .backupPath)              ?? backupPath
        backupRetentionDays     = try c.decodeIfPresent(Int.self,             forKey: .backupRetentionDays)     ?? backupRetentionDays
        lastBackupAt            = try c.decodeIfPresent(String.self,          forKey: .lastBackupAt)            ?? lastBackupAt
        defaultExportDirectory  = try c.decodeIfPresent(String.self,          forKey: .defaultExportDirectory)  ?? defaultExportDirectory
        todayQueries            = try c.decodeIfPresent([SavedQuery].self,    forKey: .todayQueries)            ?? todayQueries
        todayQueriesSeeded      = try c.decodeIfPresent(Bool.self,            forKey: .todayQueriesSeeded)      ?? todayQueriesSeeded
        goalWeightPounds        = try c.decodeIfPresent(Double.self,          forKey: .goalWeightPounds)        ?? goalWeightPounds
        startingWeightPounds    = try c.decodeIfPresent(Double.self,          forKey: .startingWeightPounds)    ?? startingWeightPounds
        heightInches            = try c.decodeIfPresent(Double.self,          forKey: .heightInches)            ?? heightInches
        forecastDays            = try c.decodeIfPresent(Int.self,             forKey: .forecastDays)            ?? forecastDays
        themeID                 = try c.decodeIfPresent(String.self,          forKey: .themeID)                 ?? themeID
        appearance              = try c.decodeIfPresent(AppearanceMode.self,  forKey: .appearance)              ?? appearance
        userThemes              = try c.decodeIfPresent([UserTheme].self,     forKey: .userThemes)              ?? userThemes
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings = AppSettings()

    private let fileURL: URL

    /// Resolves the at-rest encryption key on demand. Lets the store stay
    /// constructible without a KeyStore dependency (tests) while letting
    /// the live app inject `keyStore.currentKey` so settings.json gets
    /// wrapped via `EncryptedJSON`. A nil return value means "write
    /// plaintext", which the safeWrite path refuses to silently apply if
    /// the existing file is already ciphertext.
    private var keyResolver: () -> SymmetricKey?

    init(keyResolver: @escaping () -> SymmetricKey? = { nil }) {
        let dir = DatabaseService.supportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("settings.json")
        self.keyResolver = keyResolver
        load()
    }

    /// Re-point the resolver after construction. Needed because AppState
    /// constructs the SettingsStore early (BackupService needs it) but
    /// may not yet have a KeyStore in hand when running under test.
    func setKeyResolver(_ resolver: @escaping () -> SymmetricKey?) {
        self.keyResolver = resolver
    }

    func load() {
        guard let raw = try? Data(contentsOf: fileURL) else {
            seedTodayQueriesIfNeeded()
            return
        }
        do {
            let plain = try EncryptedJSON.unwrap(raw, key: keyResolver())
            if let decoded = try? JSONDecoder().decode(AppSettings.self, from: plain) {
                settings = decoded
            }
        } catch {
            // Encrypted on disk but no key in hand — leave defaults in
            // memory rather than silently overwriting with them. The
            // safeWrite guard in `save()` prevents an accidental
            // plaintext clobber from this state.
            NSLog("PurpleLife: settings.json read deferred — \(error.localizedDescription)")
        }
        seedTodayQueriesIfNeeded()
    }

    /// One-shot: install the default saved queries on first launch (or
    /// when the user is upgrading from a pre-Phase-3 build). Once seeded
    /// we don't re-add any, even if the user later deletes them — the
    /// `todayQueriesSeeded` flag is the gate.
    private func seedTodayQueriesIfNeeded() {
        guard !settings.todayQueriesSeeded else { return }
        if settings.todayQueries.isEmpty {
            settings.todayQueries = SavedQuerySeed.allDefaults
        }
        settings.todayQueriesSeeded = true
        save()
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        do {
            _ = try EncryptedJSON.safeWrite(data, to: fileURL, key: keyResolver())
        } catch {
            NSLog("PurpleLife: settings.json write failed — \(error.localizedDescription)")
        }
    }

    /// Active theme value, resolved against built-ins + user themes.
    /// Falls back to `.royalPurple` when the stored id isn't found
    /// (e.g. a deleted user theme that's still selected in settings).
    var currentTheme: PurpleTheme {
        PurpleTheme.resolve(id: settings.themeID, userThemes: settings.userThemes)
    }

    var resolvedBackupPath: URL {
        if settings.backupPath.isEmpty {
            return Self.downloadsDir.appendingPathComponent("PurpleLife backup", isDirectory: true)
        }
        return URL(fileURLWithPath: settings.backupPath)
    }

    var resolvedExportDirectory: URL {
        if settings.defaultExportDirectory.isEmpty {
            return Self.downloadsDir.appendingPathComponent("PurpleLife", isDirectory: true)
        }
        return URL(fileURLWithPath: settings.defaultExportDirectory)
    }

    private static var downloadsDir: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }
}
