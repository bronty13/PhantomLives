import SwiftUI
import Combine

/// Top-level observable store. Single source of truth for entries, tags,
/// people, and the per-entry join lookups, plus the current sidebar section
/// and selection. All view mutations flow through methods here — the canonical
/// pattern is `View → appState.method() → DatabaseService → reload<Slice>()`.
@MainActor
final class AppState: ObservableObject {
    // MARK: - Published slices

    @Published var entries: [Entry] = []
    @Published var tags: [Tag] = []
    @Published var people: [Person] = []
    @Published var tagsByEntry: [String: [Tag]] = [:]      // entry.id → tags
    @Published var peopleByEntry: [String: [Person]] = [:] // entry.id → people

    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    @Published var selectedSection: Section = .timeline
    @Published var selectedEntryId: String?
    @Published var searchQuery: String = ""

    // MARK: - Sections (sidebar top-level)

    enum Section: String, Hashable, CaseIterable {
        case timeline
        case calendar
        case search
        case people
        case tags

        var title: String {
            switch self {
            case .timeline: return "Timeline"
            case .calendar: return "Calendar"
            case .search:   return "Search"
            case .people:   return "People"
            case .tags:     return "Tags"
            }
        }

        var systemImage: String {
            switch self {
            case .timeline: return "list.bullet.rectangle"
            case .calendar: return "calendar"
            case .search:   return "magnifyingglass"
            case .people:   return "person.2.fill"
            case .tags:     return "tag.fill"
            }
        }
    }

    // MARK: - Sub-stores

    let settingsStore = SettingsStore()

    var settings: AppSettings {
        get { settingsStore.settings }
        set {
            settingsStore.settings = newValue
            settingsStore.save()
        }
    }

    var effectiveAccentColor: Color {
        Color(hex: settings.accentColorHex) ?? .purple
    }

    var preferredColorScheme: ColorScheme? {
        switch settings.colorScheme {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    // MARK: - Init

    init() {
        // Auto-backup-on-launch — runs synchronously before the UI reads the
        // database, so a failure here never races a partial read. Errors are
        // logged, not thrown.
        BackupService.runOnLaunchIfDue(settingsStore: settingsStore)
        try? DatabaseService.shared.seedDefaultTagsIfEmpty()
        reloadAll()
        // First-launch: seed sample entries if the journal is brand new and
        // the user has never seen samples. The flag persists across launches.
        let didInstall = SampleDataService.installIfFirstRunCompleted(
            existing: entries, settingsStore: settingsStore
        )
        if didInstall { reloadAll() }
    }

    // MARK: - Reload

    func reloadAll() {
        isLoading = true
        do {
            entries = try DatabaseService.shared.fetchAllEntries()
            tags    = try DatabaseService.shared.fetchAllTags()
            people  = try DatabaseService.shared.fetchAllPeople()
            try reloadJoins()
            if selectedEntryId == nil { selectedEntryId = entries.first?.id }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func reloadEntries() {
        do {
            entries = try DatabaseService.shared.fetchAllEntries()
            try reloadJoins()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadTags() {
        do {
            tags = try DatabaseService.shared.fetchAllTags()
            try reloadJoins()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadPeople() {
        do {
            people = try DatabaseService.shared.fetchAllPeople()
            try reloadJoins()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadJoins() throws {
        tagsByEntry = try DatabaseService.shared.tagsByEntry()
        peopleByEntry = try DatabaseService.shared.peopleByEntry()
    }

    // MARK: - Selection helpers

    var selectedEntry: Entry? {
        guard let id = selectedEntryId else { return nil }
        return entries.first { $0.id == id }
    }

    // MARK: - Entry mutations

    @discardableResult
    func createEntry(date: Date = Date(), title: String = "") throws -> Entry {
        let entry = Entry.newDraft(date: date, title: title)
        try DatabaseService.shared.insertEntry(entry)
        reloadEntries()
        selectedEntryId = entry.id
        return entry
    }

    func updateEntry(_ entry: Entry) throws {
        try DatabaseService.shared.updateEntry(entry)
        reloadEntries()
    }

    func deleteEntry(id: String) throws {
        try DatabaseService.shared.deleteEntry(id: id)
        if selectedEntryId == id { selectedEntryId = nil }
        reloadEntries()
        if selectedEntryId == nil { selectedEntryId = entries.first?.id }
    }

    // MARK: - Tag mutations

    func saveTag(_ tag: Tag) throws {
        var mutable = tag
        try DatabaseService.shared.saveTag(&mutable)
        reloadTags()
    }

    func deleteTag(id: Int64) throws {
        try DatabaseService.shared.deleteTag(id: id)
        reloadTags()
    }

    func setTags(_ tagIds: [Int64], forEntry entryId: String) throws {
        try DatabaseService.shared.setTags(tagIds, forEntry: entryId)
        try reloadJoins()
    }

    // MARK: - Person mutations

    @discardableResult
    func createPerson(name: String = "") throws -> Person {
        let p = Person.newDraft(name: name)
        try DatabaseService.shared.savePerson(p)
        reloadPeople()
        return p
    }

    func updatePerson(_ p: Person) throws {
        try DatabaseService.shared.savePerson(p)
        reloadPeople()
    }

    func deletePerson(id: String) throws {
        try DatabaseService.shared.deletePerson(id: id)
        reloadPeople()
    }

    func setPeople(_ personIds: [String], forEntry entryId: String) throws {
        try DatabaseService.shared.setPeople(personIds, forEntry: entryId)
        try reloadJoins()
    }
}
