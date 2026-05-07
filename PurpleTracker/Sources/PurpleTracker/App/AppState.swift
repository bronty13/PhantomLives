import SwiftUI
import Combine

/// Top-level observable store. Owns the cached lists of matters / types /
/// status values and per-selected-matter slices (notes, time entries,
/// attachments). All view mutations flow through methods on this type.
@MainActor
final class AppState: ObservableObject {

    // Top-level slices
    @Published var matters: [Matter] = []
    @Published var types: [MatterType] = []
    @Published var statusValues: [(name: String, sortOrder: Int)] = []
    @Published var totalSecondsByMatter: [String: Int] = [:]
    @Published var people: [Person] = []
    @Published var lastPeopleImportDate: Date?

    // Selection
    @Published var selectedMatterId: String?
    @Published var sidebarSection: SidebarSection = .all
    @Published var sidebarTypeFilter: String? = nil      // matter_type.id
    @Published var sidebarStatusFilter: String? = nil
    @Published var searchQuery: String = ""

    // Per-selected-matter slices
    @Published var notes: [Note] = []
    @Published var timeEntries: [TimeEntry] = []
    @Published var attachmentsMeta: [(id: String, filename: String, sizeBytes: Int64, mimeType: String, sha1: String, lastVerifyOk: Bool)] = []

    // Sub-stores
    let settingsStore = SettingsStore()
    @Published var errorMessage: String?

    // The timer is initialized after self so it can hold a weak ref back.
    var timer: TimerService!

    private var cancellables = Set<AnyCancellable>()

    enum SidebarSection: Hashable {
        case all
        case status(String)
        case type(String)         // matter_type.id
        case dueSoon
        case overdue
        case weeklyTimesheet

        var title: String {
            switch self {
            case .all: return "All Matters"
            case .status(let s): return s
            case .type(let id): return "Type: \(id)"
            case .dueSoon: return "Due Soon"
            case .overdue: return "Overdue"
            case .weeklyTimesheet: return "Weekly Timesheet"
            }
        }
    }

    init() {
        BackupService.runOnLaunchIfDue(settingsStore: settingsStore)
        reloadAll()
        // Attach the timer last so it can drive status auto-transitions.
        timer = TimerService(settingsStore: settingsStore, appState: self)
        // Forward the timer's per-second tick (and start/stop transitions) to
        // any view observing AppState, so the global banner and per-Matter
        // Time tab redraw live without each view having to subscribe to the
        // TimerService directly.
        timer.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Auto-import the latest ADP UserFeed if the user hasn't disabled it
        // and the most recent file in Downloads hasn't been imported before.
        autoImportPeopleIfDue()
    }

    /// Settings → People → "Auto-import on launch" controls this. Skips when
    /// the latest matching file in Downloads has already been imported (we
    /// dedupe by filename, since ADP rotates by date).
    func autoImportPeopleIfDue() {
        guard settingsStore.settings.peopleAutoImportOnLaunchEnabled else { return }
        guard let url = PeopleService.latestADPFileInDownloads() else { return }
        let fname = url.lastPathComponent
        if settingsStore.settings.lastImportedAdpFilename == fname { return }
        do {
            _ = try importPeopleCSV(at: url)
            settingsStore.settings.lastImportedAdpFilename = fname
            settingsStore.save()
        } catch {
            errorMessage = "ADP auto-import failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Reload

    func reloadAll() {
        do {
            types = try DatabaseService.shared.fetchAllTypes()
            statusValues = try DatabaseService.shared.fetchStatusValues()
            matters = try DatabaseService.shared.fetchAllMatters()
            try recomputeTotals()
            reloadPeople()
            if let sid = selectedMatterId {
                try loadSelected(sid)
            } else if let first = matters.first {
                selectedMatterId = first.id
                try loadSelected(first.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadMatters() {
        do {
            matters = try DatabaseService.shared.fetchAllMatters()
            try recomputeTotals()
        } catch { errorMessage = error.localizedDescription }
    }

    func reloadPeople() {
        do {
            people = try PeopleService.fetchAll()
            lastPeopleImportDate = try PeopleService.lastImportDate()
        } catch { errorMessage = error.localizedDescription }
    }

    /// O(1) lookup for the Matter detail view's Requestor display.
    var peopleById: [String: Person] {
        Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
    }

    func importPeopleCSV(at url: URL) throws -> PeopleService.ImportResult {
        let result = try PeopleService.importCSV(at: url)
        reloadPeople()
        return result
    }

    func reloadTimeEntries() {
        guard let id = selectedMatterId else { return }
        do {
            timeEntries = try DatabaseService.shared.fetchTimeEntries(matterId: id)
            try recomputeTotals()
        } catch { errorMessage = error.localizedDescription }
    }

    func selectMatter(id: String) {
        selectedMatterId = id
        do {
            try DatabaseService.shared.touchAccessed(matterId: id)
            try loadSelected(id)
            // Refresh the in-memory matter so the UI sees the bumped accessed_at.
            if let updated = try DatabaseService.shared.fetchMatter(id: id),
               let idx = matters.firstIndex(where: { $0.id == id }) {
                matters[idx] = updated
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func loadSelected(_ id: String) throws {
        notes = try DatabaseService.shared.fetchNotes(matterId: id)
        timeEntries = try DatabaseService.shared.fetchTimeEntries(matterId: id)
        attachmentsMeta = try DatabaseService.shared.fetchAttachmentMetadata(matterId: id)
    }

    private func recomputeTotals() throws {
        // One sweep through all entries — small enough that an in-memory
        // group-by is faster than per-matter SQL queries.
        let all = try DatabaseService.shared.fetchAllTimeEntries()
        var byMatter: [String: Int] = [:]
        for e in all {
            byMatter[e.matterId, default: 0] += e.seconds
        }
        totalSecondsByMatter = byMatter
    }

    // MARK: - Computed slices

    var selectedMatter: Matter? {
        guard let id = selectedMatterId else { return nil }
        return matters.first { $0.id == id }
    }

    var typesById: [String: MatterType] {
        Dictionary(uniqueKeysWithValues: types.map { ($0.id, $0) })
    }

    var filteredMatters: [Matter] {
        var rows = matters
        switch sidebarSection {
        case .all: break
        case .status(let s): rows = rows.filter { $0.status == s }
        case .type(let id):  rows = rows.filter { $0.typeId == id }
        case .dueSoon:
            let cutoff = Date().addingTimeInterval(7 * 86400)
            rows = rows.filter { ($0.dueAt ?? .distantFuture) <= cutoff && $0.status != "Closed" }
        case .overdue:
            let now = Date()
            rows = rows.filter { ($0.dueAt ?? .distantFuture) < now && $0.status != "Closed" }
        case .weeklyTimesheet:
            break  // handled by ContentView routing; matter list is hidden
        }
        if let t = sidebarTypeFilter   { rows = rows.filter { $0.typeId == t } }
        if let s = sidebarStatusFilter { rows = rows.filter { $0.status == s } }
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            // Capturing peopleById once avoids rebuilding the dictionary
            // inside the per-row closure (filteredMatters is a computed
            // property that re-evaluates on every state change).
            let lookup = peopleById
            // Resolve a matter's internal-people slots to their searchable
            // display strings (name + title + email) so name searches hit.
            func partyText(_ aid: String) -> String {
                guard !aid.isEmpty, let p = lookup[aid] else { return "" }
                return "\(p.displayName) \(p.jobTitle) \(p.workEmail)".lowercased()
            }
            rows = rows.filter { m in
                if m.title.lowercased().contains(q) { return true }
                if m.id.lowercased().contains(q) { return true }
                if m.descriptionMd.lowercased().contains(q) { return true }
                if m.notesMd.lowercased().contains(q) { return true }
                if partyText(m.requestorAssociateId).contains(q) { return true }
                let ips = [
                    m.interestedParty1AssociateId, m.interestedParty2AssociateId,
                    m.interestedParty3AssociateId, m.interestedParty4AssociateId,
                    m.interestedParty5AssociateId
                ]
                if ips.contains(where: { partyText($0).contains(q) }) { return true }
                let externals = [
                    m.externalInterestedParty1, m.externalInterestedParty2,
                    m.externalInterestedParty3, m.externalInterestedParty4,
                    m.externalInterestedParty5
                ]
                if externals.contains(where: { $0.lowercased().contains(q) }) { return true }
                return false
            }
        }
        return rows
    }

    // MARK: - Matter mutations

    @discardableResult
    func createMatter(typeId: String, title: String = "") throws -> Matter {
        let now = Date()
        var inserted: Matter?
        let id = try MatterIDService.allocateAndInsert(on: now, in: DatabaseService.shared.dbPool) { db, mid in
            let resolved = self.resolveDefaultPaths(title: title, matterId: mid)
            var m = Matter.newDraft(id: mid, typeId: typeId, title: title)
            m.fileStorePrimary = resolved.primary
            m.fileStoreSecondary = resolved.secondary
            try m.insert(db)
            inserted = m
        }
        reloadMatters()
        selectMatter(id: id)
        return inserted!
    }

    private func resolveDefaultPaths(title: String, matterId: String) -> (primary: String, secondary: String) {
        let s = settingsStore.settings
        let primary = FileStoreService.render(template: s.fileStorePrimaryTemplate, title: title, matterId: matterId)
        let secondary = FileStoreService.render(template: s.fileStoreSecondaryTemplate, title: title, matterId: matterId)
        return (primary, secondary)
    }

    func updateMatter(_ m: Matter) throws {
        var next = m
        // If the title changed AND the file-store paths still match what we'd
        // template from the *previous* title (i.e. the user hasn't manually
        // edited them), retemplate with the new title. This makes the common
        // case "click New Matter → type a title" do the right thing, while
        // preserving any manual customisation the user has made to the paths.
        if let prior = matters.first(where: { $0.id == m.id }),
           prior.title != m.title {
            let priorResolved = resolveDefaultPaths(title: prior.title, matterId: m.id)
            let newResolved = resolveDefaultPaths(title: m.title, matterId: m.id)
            if next.fileStorePrimary == priorResolved.primary {
                next.fileStorePrimary = newResolved.primary
            }
            if next.fileStoreSecondary == priorResolved.secondary {
                next.fileStoreSecondary = newResolved.secondary
            }
        }
        try DatabaseService.shared.updateMatter(next)
        reloadMatters()
        if next.id == selectedMatterId,
           let updated = try DatabaseService.shared.fetchMatter(id: next.id),
           let idx = matters.firstIndex(where: { $0.id == next.id }) {
            matters[idx] = updated
        }
    }

    /// Apply a status change. If the new status is the lifecycle's terminal
    /// value (last by sort_order — typically "Closed") AND the matter has a
    /// cadence, spawn the next instance.
    func updateMatterStatus(_ matter: Matter, to newStatus: String) throws {
        var m = matter
        m.status = newStatus
        try updateMatter(m)

        let terminal = statusValues.last?.name ?? "Closed"
        if newStatus == terminal,
           let cadenceId = matter.cadenceId,
           let cadence = try DatabaseService.shared.fetchCadence(id: cadenceId) {
            let template = CadenceService.nextMatter(after: matter, cadence: cadence)
            try MatterIDService.allocateAndInsert(in: DatabaseService.shared.dbPool) { db, mid in
                var next = template
                next.id = mid
                let resolved = self.resolveDefaultPaths(title: next.title, matterId: mid)
                next.fileStorePrimary = resolved.primary
                next.fileStoreSecondary = resolved.secondary
                try next.insert(db)
            }
            reloadMatters()
        }
    }

    /// Called by `TimerService.start` — bump status from the lifecycle's
    /// first value (typically "New") to the second (typically "In-Progress"),
    /// keyed off `sort_order` so renames are safe.
    func bumpToInProgressIfNew(matterId: String) {
        guard let matter = matters.first(where: { $0.id == matterId }),
              statusValues.count >= 2,
              matter.status == statusValues[0].name
        else { return }
        var m = matter
        m.status = statusValues[1].name
        try? updateMatter(m)
    }

    func deleteMatter(id: String) throws {
        try DatabaseService.shared.deleteMatter(id: id)
        if selectedMatterId == id { selectedMatterId = nil }
        reloadAll()
    }

    // MARK: - Note mutations

    func addNote(body: String) throws {
        guard let mid = selectedMatterId else { return }
        let now = Date()
        let n = Note(id: UUID().uuidString, matterId: mid, bodyMd: body, createdAt: now, updatedAt: now)
        try DatabaseService.shared.saveNote(n)
        notes = try DatabaseService.shared.fetchNotes(matterId: mid)
    }

    func updateNote(_ n: Note) throws {
        var updated = n
        updated.updatedAt = Date()
        try DatabaseService.shared.saveNote(updated)
        if let mid = selectedMatterId {
            notes = try DatabaseService.shared.fetchNotes(matterId: mid)
        }
    }

    func deleteNote(id: String) throws {
        try DatabaseService.shared.deleteNote(id: id)
        if let mid = selectedMatterId {
            notes = try DatabaseService.shared.fetchNotes(matterId: mid)
        }
    }

    // MARK: - Attachments

    func addAttachment(fileURL: URL) throws {
        guard let mid = selectedMatterId else { return }
        let a = try AttachmentService.ingest(fileURL: fileURL, matterId: mid)
        try DatabaseService.shared.insertAttachment(a)
        attachmentsMeta = try DatabaseService.shared.fetchAttachmentMetadata(matterId: mid)
    }

    /// Read the BLOB, verify SHA1, and write it to a temp file so the user
    /// can open / preview it. Returns (tempURL, verified).
    func openAttachment(id attachmentId: String) throws -> (url: URL, verified: Bool) {
        let pool = DatabaseService.shared.dbPool
        let attachment: Attachment? = try pool.read { db in
            try Attachment.fetchOne(db, key: attachmentId)
        }
        guard let a = attachment else {
            throw NSError(domain: "PurpleTracker", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "Attachment not found"])
        }
        let verified = AttachmentService.verify(a)
        try DatabaseService.shared.updateAttachmentVerification(id: a.id, at: Date(), ok: verified)
        if let mid = selectedMatterId {
            attachmentsMeta = try DatabaseService.shared.fetchAttachmentMetadata(matterId: mid)
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pt-\(a.id)-\(a.filename)")
        try? FileManager.default.removeItem(at: tempURL)
        try a.data.write(to: tempURL)
        return (tempURL, verified)
    }

    func deleteAttachment(id: String) throws {
        try DatabaseService.shared.deleteAttachment(id: id)
        if let mid = selectedMatterId {
            attachmentsMeta = try DatabaseService.shared.fetchAttachmentMetadata(matterId: mid)
        }
    }

    // MARK: - Type / status / cadence settings mutations

    func saveType(_ t: MatterType) throws {
        try DatabaseService.shared.saveType(t)
        types = try DatabaseService.shared.fetchAllTypes()
    }

    func deleteType(id: String) throws {
        // Don't allow deletion of a type still in use — block at the UI layer.
        try DatabaseService.shared.deleteType(id: id)
        types = try DatabaseService.shared.fetchAllTypes()
    }

    func saveStatusValues(_ values: [(name: String, sortOrder: Int)]) throws {
        try DatabaseService.shared.replaceStatusValues(values)
        statusValues = try DatabaseService.shared.fetchStatusValues()
    }

    func saveCadence(_ c: Cadence) throws {
        try DatabaseService.shared.saveCadence(c)
    }

    // MARK: - Backup actions

    func runBackupNow() throws -> URL {
        try BackupService.doBackup(settingsStore: settingsStore)
    }

    /// Runs a pre-restore safety backup, then restores from `archiveURL`,
    /// then reopens the GRDB pool and reloads everything.
    func restoreBackup(_ archiveURL: URL) throws {
        _ = try BackupService.doBackup(settingsStore: settingsStore)  // safety backup first
        try BackupService.restoreArchive(at: archiveURL, into: DatabaseService.supportDirectory)
        try DatabaseService.shared.reopenDatabase()
        settingsStore.load()
        reloadAll()
    }
}
