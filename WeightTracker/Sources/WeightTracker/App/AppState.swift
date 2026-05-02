import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var entries: [WeightEntry] = []
    @Published var stats: WeightStats? = nil
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    let settingsStore = SettingsStore()

    var settings: AppSettings {
        get { settingsStore.settings }
        set { settingsStore.settings = newValue; settingsStore.save() }
    }

    var currentTheme: Theme {
        Theme.named(settings.themeName)
    }

    var effectiveAccentColor: Color {
        Color(hex: settings.accentColorHex) ?? currentTheme.accentColor
    }

    var effectiveFont: Font {
        if settings.fontName.isEmpty {
            return .system(size: settings.fontSize)
        }
        return .custom(settings.fontName, size: settings.fontSize)
    }

    init() {
        loadFromDatabase()
        runBackup()
    }

    func loadFromDatabase() {
        isLoading = true
        do {
            entries = try DatabaseService.shared.fetchAll()
            recomputeStats()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func recomputeStats() {
        stats = StatisticsService.compute(entries: entries, settings: settings)
    }

    func addEntry(_ entry: inout WeightEntry) {
        do {
            try DatabaseService.shared.insert(&entry)
            loadFromDatabase()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateEntry(_ entry: WeightEntry) {
        do {
            try DatabaseService.shared.update(entry)
            loadFromDatabase()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteEntry(id: Int64) {
        do {
            try DatabaseService.shared.delete(id: id)
            loadFromDatabase()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteEntries(ids: [Int64]) {
        do {
            try DatabaseService.shared.deleteAll(ids: ids)
            loadFromDatabase()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importEntries(_ parsed: [ParsedEntry]) {
        for p in parsed where p.isSelected {
            let now = isoNow()
            var entry = WeightEntry(
                rowId: nil,
                date: p.date,
                weightLbs: p.weightLbs,
                notesMd: "",
                photoBlob: nil,
                photoFilename: nil,
                photoExt: nil,
                createdAt: now,
                updatedAt: now
            )
            try? DatabaseService.shared.insert(&entry)
        }
        loadFromDatabase()
    }

    private func runBackup() {
        BackupService.runIfEnabled(settings: settings, backupURL: settingsStore.resolvedBackupPath)
    }

    func existingDates() -> Set<String> {
        Set(entries.map { $0.date })
    }

    private func isoNow() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: Date())
    }
}
