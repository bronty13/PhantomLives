import Foundation

struct AppSettings: Codable {
    // Appearance
    var themeName: String = "Default"
    var fontName: String = ""
    var fontSize: Double = 13
    var accentColorHex: String = "#3B82F6"     // blue — overrides the theme accent if set
    var colorScheme: String = "auto"           // "auto" | "light" | "dark"

    // Defaults
    var defaultCaseStatus: String = CaseStatus.active.rawValue
    var defaultImportance: String = Importance.medium.rawValue
    var dateFormatStyle: String = "medium"     // "short" | "medium" | "long" | "full"
    var weekStartsMonday: Bool = false

    // Backup (auto-runs at every launch by default — PhantomLives convention)
    var autoBackupEnabled: Bool = true
    var backupPath: String = ""                // empty → resolvedBackupPath default
    var backupRetentionDays: Int = 14
    var lastBackupAt: String = ""              // ISO-8601, empty if never

    // Export
    var defaultExportDirectory: String = ""    // empty → resolvedExportDirectory default

    // Search
    var includeNotesInSearch: Bool = true

    // Per-role overrides (UUID-style keyed dict; rawValue → hex). Empty means
    // "use PersonRole.defaultColorHex".
    var roleColorOverrides: [String: String] = [:]

    // Custom user-authored themes. The active theme is selected via
    // `themeName` — for built-ins that's the theme's name (e.g. "Midnight"),
    // for user themes it's `user:<uuid>`. Theme.named() resolves both.
    var userThemes: [UserTheme] = []

    // Per-slot font customization. Keyed by FontSlot.rawValue. Missing keys
    // fall back to the slot's `defaultStyle`.
    var fontSlots: [String: FontStyle] = [:]

    // Anniversary reminders (UNUserNotificationCenter).
    var anniversaryRemindersEnabled: Bool = false
    var anniversaryLookaheadDays: Int = 30
    var anniversaryNotificationHour: Int = 9
    var anniversaryMinImportance: String = Importance.medium.rawValue

    // Sample data — one-shot flag so the first launch installs the shipped
    // sample cases, but a subsequent delete isn't silently undone next time
    // the app starts. The "Restore Sample Data" button in Settings → General
    // is the explicit re-add path.
    var sampleDataEverInstalled: Bool = false
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings = AppSettings()

    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Timeliner", isDirectory: true)
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
            return Self.downloadsDir.appendingPathComponent("Timeliner backup", isDirectory: true)
        }
        return URL(fileURLWithPath: settings.backupPath)
    }

    var resolvedExportDirectory: URL {
        if settings.defaultExportDirectory.isEmpty {
            return Self.downloadsDir.appendingPathComponent("Timeliner", isDirectory: true)
        }
        return URL(fileURLWithPath: settings.defaultExportDirectory)
    }

    func roleColorHex(for role: PersonRole) -> String {
        settings.roleColorOverrides[role.rawValue] ?? role.defaultColorHex
    }

    func setRoleColor(_ hex: String, for role: PersonRole) {
        var s = settings
        s.roleColorOverrides[role.rawValue] = hex
        settings = s
        save()
    }

    private static var downloadsDir: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }
}
