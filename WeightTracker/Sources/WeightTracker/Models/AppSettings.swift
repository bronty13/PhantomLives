import Foundation

enum ChartStyle: String, Codable, CaseIterable {
    case line, bar, area, scatter, movingAverage

    var label: String {
        switch self {
        case .line: return "Line"
        case .bar: return "Bar"
        case .area: return "Area"
        case .scatter: return "Scatter"
        case .movingAverage: return "Moving Avg"
        }
    }
}

struct AppSettings: Codable {
    var username: String = "Me"
    var goalWeight: Double? = nil
    var startingWeight: Double? = nil
    var weightUnit: WeightUnit = .lbs
    var heightInches: Double? = nil
    var themeName: String = "Default"
    var fontName: String = ""
    var fontSize: Double = 13
    var accentColorHex: String = "#0A84FF"
    var chartStyle: ChartStyle = .line
    var showTrendLine: Bool = true
    var showGoalLine: Bool = true
    var autoBackupEnabled: Bool = true
    var backupPath: String = ""
    var backupRetentionDays: Int = 30
    var forecastDays: Int = 30
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings = AppSettings()

    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("WeightTracker", isDirectory: true)
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
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    var effectiveStartingWeight: Double? {
        settings.startingWeight
    }

    var resolvedBackupPath: URL {
        if settings.backupPath.isEmpty {
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            return downloads.appendingPathComponent("WeightTracker", isDirectory: true)
        }
        return URL(fileURLWithPath: settings.backupPath)
    }
}
