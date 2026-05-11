import Foundation

/// Persisted to `~/Library/Application Support/PurpleLife/settings.json`.
/// Phase 1 only carries the four backup-related keys mandated by
/// `CLAUDE.md` plus the export-directory override; later phases extend
/// this struct in place — Codable's missing-key tolerance keeps reads of
/// older settings.json files compatible without a migration.
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
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings = AppSettings()

    private let fileURL: URL

    init() {
        let dir = DatabaseService.supportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("settings.json")
        load()
    }

    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
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
        try? data.write(to: fileURL, options: .atomic)
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
