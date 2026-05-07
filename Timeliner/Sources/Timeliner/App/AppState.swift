import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    // MARK: - Published slices

    @Published var cases: [Case] = []
    @Published var events: [Event] = []
    @Published var tags: [Tag] = []
    @Published var people: [Person] = []
    @Published var tagsByEvent: [String: [Tag]] = [:]      // event.id → tags
    @Published var peopleByEvent: [String: [Person]] = [:] // event.id → people
    /// event.id → attachment count. Populated by `reloadJoins` so the
    /// timeline rows can show a "📎 N" indicator without per-row DB hits.
    @Published var attachmentCounts: [String: Int] = [:]

    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    @Published var selectedSection: Section = .dashboard
    @Published var selectedCaseId: String?

    // MARK: - Filters (apply to the current case timeline view)

    @Published var dateRangeFilter: DateInterval?
    @Published var tagFilter: Set<Int64> = []
    @Published var importanceFilter: Set<Importance> = []
    @Published var searchQuery: String = ""

    // MARK: - Sections (sidebar top-level)

    enum Section: String, Hashable, CaseIterable {
        case dashboard
        case allCases
        case crossCase
        case people
        case tags
        case search

        var title: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .allCases:  return "All Cases"
            case .crossCase: return "Cross-case Timeline"
            case .people:    return "People"
            case .tags:      return "Tags"
            case .search:    return "Search"
            }
        }

        var systemImage: String {
            switch self {
            case .dashboard: return "rectangle.3.group.fill"
            case .allCases:  return "folder.fill"
            case .crossCase: return "rectangle.split.3x1"
            case .people:    return "person.2.fill"
            case .tags:      return "tag.fill"
            case .search:    return "magnifyingglass"
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
            // Anniversary reminder schedule is keyed off settings, so any
            // settings change (toggle on/off, lookahead change, importance
            // floor change, hour change) needs to rebuild the schedule.
            scheduleAnniversaryReminders()
        }
    }

    var currentTheme: Theme {
        Theme.named(settings.themeName, userThemes: settings.userThemes)
    }

    /// Resolved font for a named slot — uses the user's override if present,
    /// falls back to the slot's default. Views call this everywhere they
    /// previously hard-coded `.font(.body)` etc.
    func font(for slot: FontSlot) -> Font {
        (settings.fontSlots[slot.rawValue] ?? slot.defaultStyle).swiftUIFont()
    }

    var effectiveAccentColor: Color {
        Color(hex: settings.accentColorHex) ?? currentTheme.accentColor
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
        // Auto-backup-on-launch — the PhantomLives convention. Runs synchronously
        // before the UI begins reading the database, so a failure here never
        // races a partial DB read. Errors are logged, not thrown.
        BackupService.runOnLaunchIfDue(settingsStore: settingsStore)
        reloadAll()
    }

    // MARK: - Reload

    func reloadAll() {
        isLoading = true
        do {
            cases  = try DatabaseService.shared.fetchAllCases()
            events = try DatabaseService.shared.fetchAllEvents()
            tags   = try DatabaseService.shared.fetchAllTags()
            people = try DatabaseService.shared.fetchAllPeople()
            try reloadJoins()
            // Auto-select the first case if none selected and at least one exists,
            // so the case-detail view has something to show on launch.
            if selectedCaseId == nil { selectedCaseId = cases.first?.id }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        scheduleAnniversaryReminders()
    }

    func reloadCases() {
        do { cases = try DatabaseService.shared.fetchAllCases() }
        catch { errorMessage = error.localizedDescription }
    }

    func reloadEvents() {
        do {
            events = try DatabaseService.shared.fetchAllEvents()
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

    /// Rebuild the anniversary reminder set off the current data + settings.
    /// Cheap because UNUserNotificationCenter handles diffing internally; we
    /// always wipe-and-replace the Timeliner-owned reminders.
    func scheduleAnniversaryReminders() {
        let events = self.events
        let cases = self.cases
        let settings = self.settings
        Task { @MainActor in
            await NotificationsService.shared.reschedule(events: events, cases: cases, settings: settings)
        }
    }

    private func reloadJoins() throws {
        var tagsByEvent: [String: [Tag]] = [:]
        var peopleByEvent: [String: [Person]] = [:]
        let allCases = self.cases
        for c in allCases {
            let caseTags = try DatabaseService.shared.tagsByEvent(in: c.id)
            for (eid, list) in caseTags { tagsByEvent[eid] = list }
        }
        // People-by-event is reasonably small; resolve via a single per-event query.
        for ev in events {
            let pids = try DatabaseService.shared.personIDs(forEvent: ev.id)
            if pids.isEmpty { continue }
            peopleByEvent[ev.id] = people.filter { pids.contains($0.id) }
        }
        // One bulk query for attachment counts so the timeline can show
        // the paperclip badge without N round trips.
        let attachmentCounts = try DatabaseService.shared.attachmentCounts(parentType: .event)
        self.tagsByEvent = tagsByEvent
        self.peopleByEvent = peopleByEvent
        self.attachmentCounts = attachmentCounts
    }

    // MARK: - Selection helpers

    var selectedCase: Case? {
        guard let id = selectedCaseId else { return nil }
        return cases.first { $0.id == id }
    }

    func eventsForSelectedCase() -> [Event] {
        guard let id = selectedCaseId else { return [] }
        return events.filter { $0.caseId == id }
    }

    func peopleForSelectedCase() -> [Person] {
        guard let id = selectedCaseId else { return [] }
        return people.filter { $0.caseId == id }
    }

    // MARK: - Case mutations

    @discardableResult
    func createCase(title: String) throws -> Case {
        let aCase = Case.newDraft(title: title)
        try DatabaseService.shared.insertCase(aCase)
        reloadCases()
        selectedCaseId = aCase.id
        return aCase
    }

    func updateCase(_ aCase: Case) throws {
        try DatabaseService.shared.updateCase(aCase)
        reloadCases()
    }

    func deleteCase(id: String) throws {
        // Wipe attachments tied to the case itself + every event + every
        // person in the case. The DB's FKs cascade events/people but the
        // attachments table is polymorphic with no real FK, so we have to
        // do it ourselves.
        let eventIds = events.filter { $0.caseId == id }.map(\.id)
        let personIds = people.filter { $0.caseId == id }.map(\.id)
        try DatabaseService.shared.deleteAttachments(parentType: .caseRecord, parentId: id)
        for eid in eventIds {
            try DatabaseService.shared.deleteAttachments(parentType: .event, parentId: eid)
        }
        for pid in personIds {
            try DatabaseService.shared.deleteAttachments(parentType: .person, parentId: pid)
        }

        try DatabaseService.shared.deleteCase(id: id)
        if selectedCaseId == id { selectedCaseId = nil }
        reloadAll()
    }

    func togglePin(caseId: String) throws {
        guard var c = cases.first(where: { $0.id == caseId }) else { return }
        c.pinned.toggle()
        try updateCase(c)
    }

    // MARK: - Event mutations

    @discardableResult
    func createEvent(caseId: String, date: Date = Date(), title: String = "") throws -> Event {
        var ev = Event.newDraft(caseId: caseId, date: date)
        ev.title = title
        try DatabaseService.shared.insertEvent(ev)
        reloadEvents()
        // Bump the case's updated_at so it floats to the top of the list.
        // updateCase() stamps the timestamp itself, so we just pass the row through.
        if let c = cases.first(where: { $0.id == caseId }) {
            try? DatabaseService.shared.updateCase(c)
            reloadCases()
        }
        return ev
    }

    func updateEvent(_ event: Event) throws {
        try DatabaseService.shared.updateEvent(event)
        reloadEvents()
    }

    func deleteEvent(id: String) throws {
        try DatabaseService.shared.deleteAttachments(parentType: .event, parentId: id)
        try DatabaseService.shared.deleteEvent(id: id)
        reloadEvents()
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

    func setTags(_ tagIds: [Int64], forEvent eventId: String) throws {
        try DatabaseService.shared.setTags(tagIds, forEvent: eventId)
        try reloadJoins()
    }

    // MARK: - Person mutations

    @discardableResult
    func createPerson(caseId: String, role: PersonRole = .other, name: String = "") throws -> Person {
        var p = Person.newDraft(caseId: caseId, role: role)
        p.name = name
        try DatabaseService.shared.savePerson(p)
        reloadPeople()
        return p
    }

    func updatePerson(_ p: Person) throws {
        try DatabaseService.shared.savePerson(p)
        reloadPeople()
    }

    func deletePerson(id: String) throws {
        try DatabaseService.shared.deleteAttachments(parentType: .person, parentId: id)
        try DatabaseService.shared.deletePerson(id: id)
        reloadPeople()
    }

    func setPeople(_ personIds: [String], forEvent eventId: String) throws {
        try DatabaseService.shared.setPeople(personIds, forEvent: eventId)
        try reloadJoins()
    }
}
