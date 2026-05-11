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
    @Published var initiatives: [Initiative] = []
    @Published var goals: [Goal] = []
    /// matterId → initiativeIds; rebuilt from the join table on every reloadAll.
    @Published var matterInitiativeIds: [String: Set<String>] = [:]
    /// matterId → goalIds.
    @Published var matterGoalIds: [String: Set<String>] = [:]

    // 1.3.0 — Subtasks, links, audit, saved searches, trash
    @Published var trashedMatters: [Matter] = []
    @Published var subtasksByMatter: [String: [Subtask]] = [:]
    @Published var subtaskCounts: [String: (done: Int, total: Int)] = [:]
    @Published var linksByMatter: [String: [MatterLink]] = [:]
    @Published var auditEvents: [AuditEvent] = []
    @Published var savedSearches: [SavedSearch] = []
    @Published var activeSavedSearchId: String? = nil
    /// One-shot toast hint shown after a soft-delete so the user can undo.
    @Published var lastDeletedMatterId: String? = nil
    /// ⌘K command palette is shown when this is true; flipped from
    /// `PurpleTrackerApp` menu commands.
    @Published var commandPaletteVisible: Bool = false

    // 1.4.0 — Third Parties (vendors)
    @Published var vendors: [Vendor] = []
    @Published var selectedVendorId: String?
    @Published var vendorContacts: [VendorContact] = []
    @Published var vendorProducts: [VendorProduct] = []
    @Published var vendorYearAmounts: [VendorYearAmount] = []
    @Published var vendorInvoices: [VendorInvoice] = []
    @Published var vendorNotes: [VendorNote] = []
    /// Cached effective-actuals (override ?? sum-of-invoices) keyed by year
    /// for the currently selected vendor. Recomputed on any invoice or
    /// override change so the matrix updates without manual refresh.
    @Published var vendorEffectiveActuals: [Int: Int64] = [:]

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
        case today                // 1.3.0 — Today / Up Next dashboard
        case timeDashboard        // 1.3.0 — Time charts
        case analytics            // 1.3.0 — Matter analytics
        case capacity             // 1.3.0 — Per-person capacity
        case trash                // 1.3.0 — Soft-deleted Matters
        case savedSearch(String)  // 1.3.0 — Saved-search id
        case thirdPartiesAll      // 1.4.0 — All Third Parties list
        case noteType(String)     // 1.5.0 — Notes workspace, by type id

        var title: String {
            switch self {
            case .all: return "All Matters"
            case .status(let s): return s
            case .type(let id): return "Type: \(id)"
            case .dueSoon: return "Due Soon"
            case .overdue: return "Overdue"
            case .weeklyTimesheet: return "Weekly Timesheet"
            case .today: return "Today"
            case .timeDashboard: return "Time Dashboard"
            case .analytics: return "Analytics"
            case .capacity: return "Capacity"
            case .trash: return "Trash"
            case .savedSearch(let id): return "Saved: \(id)"
            case .thirdPartiesAll: return "Third Parties"
            case .noteType(let id): return "Notes: \(id)"
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
            initiatives = try DatabaseService.shared.fetchAllInitiatives()
            goals = try DatabaseService.shared.fetchAllGoals()
            matters = try DatabaseService.shared.fetchAllMatters()
            try recomputeTotals()
            try reloadInitiativeAndGoalLinks()
            reloadPeople()
            try reloadSubtaskCounts()
            try reloadLinks()
            try reloadSavedSearches()
            try reloadTrash()
            try reloadVendors()
            try reloadNoteTypes()
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
            try reloadSubtaskCounts()
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
        subtasksByMatter[id] = try DatabaseService.shared.fetchSubtasks(matterId: id)
        auditEvents = try DatabaseService.shared.fetchAuditEvents(matterId: id)
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
        case .today, .timeDashboard, .analytics, .capacity:
            break  // dedicated dashboards take over the detail pane
        case .thirdPartiesAll:
            return []  // Third Parties UI replaces the matter list
        case .noteType:
            return []  // Notes workspace replaces the matter list
        case .trash:
            // Trash bin uses its own data slice (`trashedMatters`); the
            // main list shows nothing while in this section.
            return []
        case .savedSearch(let id):
            if let s = savedSearches.first(where: { $0.id == id }) {
                rows = applySavedSearch(s.criteria, to: rows)
            }
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
            // Seed an audit "created" event so the History tab always has
            // a starting point.
            var ev = AuditEvent(id: UUID().uuidString, matterId: mid, ts: now,
                                kind: "created", beforeValue: "", afterValue: title)
            try ev.insert(db)
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
        // Capture audit deltas vs. the in-memory prior copy. A handful of
        // user-facing field changes (status, priority, type, title) are
        // recorded as audit events so the History tab can show a timeline.
        let prior = matters.first(where: { $0.id == m.id })
        // If the title changed AND the file-store paths still match what we'd
        // template from the *previous* title (i.e. the user hasn't manually
        // edited them), retemplate with the new title. This makes the common
        // case "click New Matter → type a title" do the right thing, while
        // preserving any manual customisation the user has made to the paths.
        if let p = prior, p.title != m.title {
            let priorResolved = resolveDefaultPaths(title: p.title, matterId: m.id)
            let newResolved = resolveDefaultPaths(title: m.title, matterId: m.id)
            if next.fileStorePrimary == priorResolved.primary {
                next.fileStorePrimary = newResolved.primary
            }
            if next.fileStoreSecondary == priorResolved.secondary {
                next.fileStoreSecondary = newResolved.secondary
            }
        }
        try DatabaseService.shared.updateMatter(next)
        if let p = prior {
            emitAuditDeltas(for: m.id, before: p, after: next)
        }
        reloadMatters()
        if next.id == selectedMatterId,
           let updated = try DatabaseService.shared.fetchMatter(id: next.id),
           let idx = matters.firstIndex(where: { $0.id == next.id }) {
            matters[idx] = updated
            // Refresh the audit feed so the new event appears immediately.
            auditEvents = (try? DatabaseService.shared.fetchAuditEvents(matterId: next.id)) ?? auditEvents
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
            var newId: String = ""
            try MatterIDService.allocateAndInsert(in: DatabaseService.shared.dbPool) { db, mid in
                var next = template
                next.id = mid
                let resolved = self.resolveDefaultPaths(title: next.title, matterId: mid)
                next.fileStorePrimary = resolved.primary
                next.fileStoreSecondary = resolved.secondary
                try next.insert(db)
                newId = mid
            }
            // Carry initiative + goal tags over to the spawned successor.
            if !newId.isEmpty {
                try DatabaseService.shared.copyMatterTags(from: matter.id, to: newId)
            }
            reloadMatters()
            try reloadInitiativeAndGoalLinks()
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

    /// Soft-delete: move to Trash. The Matter remains in the DB so links and
    /// time entries are preserved; the 30-day purge sweep on launch hard-
    /// deletes anything older than that. Use `restoreMatter` to recover.
    func deleteMatter(id: String) throws {
        guard var m = matters.first(where: { $0.id == id })
            ?? (try? DatabaseService.shared.fetchMatter(id: id)) else {
            return
        }
        m.deletedAt = Date()
        try DatabaseService.shared.updateMatter(m)
        try DatabaseService.shared.appendAuditEvent(AuditEvent(
            id: UUID().uuidString, matterId: id, ts: Date(),
            kind: "deleted", beforeValue: "", afterValue: ""
        ))
        if selectedMatterId == id { selectedMatterId = nil }
        lastDeletedMatterId = id
        reloadMatters()
        try? reloadTrash()
    }

    /// Permanently delete a Matter from the Trash bin (cascades).
    func purgeMatter(id: String) throws {
        try DatabaseService.shared.deleteMatter(id: id)
        if selectedMatterId == id { selectedMatterId = nil }
        try? reloadTrash()
        reloadMatters()
    }

    func restoreMatter(id: String) throws {
        guard var m = try DatabaseService.shared.fetchMatter(id: id) else { return }
        m.deletedAt = nil
        try DatabaseService.shared.updateMatter(m)
        try DatabaseService.shared.appendAuditEvent(AuditEvent(
            id: UUID().uuidString, matterId: id, ts: Date(),
            kind: "restored", beforeValue: "", afterValue: ""
        ))
        try? reloadTrash()
        reloadMatters()
    }

    /// Hard-delete trashed matters older than 30 days. Run on launch.
    func purgeExpiredTrash(olderThanDays days: Int = 30) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        _ = try? DatabaseService.shared.purgeTrashOlderThan(cutoff)
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

    // MARK: - Initiatives / Goals

    /// Rebuilds the per-Matter sets of initiative and goal IDs from the
    /// join tables. Called from `reloadAll` and after any link mutation.
    func reloadInitiativeAndGoalLinks() throws {
        var initMap: [String: Set<String>] = [:]
        for link in try DatabaseService.shared.fetchAllMatterInitiativeLinks() {
            initMap[link.matterId, default: []].insert(link.initiativeId)
        }
        var goalMap: [String: Set<String>] = [:]
        for link in try DatabaseService.shared.fetchAllMatterGoalLinks() {
            goalMap[link.matterId, default: []].insert(link.goalId)
        }
        matterInitiativeIds = initMap
        matterGoalIds = goalMap
    }

    /// O(1) lookups used by detail views to render names from IDs.
    var initiativesById: [String: Initiative] {
        Dictionary(uniqueKeysWithValues: initiatives.map { ($0.id, $0) })
    }
    var goalsById: [String: Goal] {
        Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0) })
    }

    func saveInitiative(_ i: Initiative) throws {
        try DatabaseService.shared.saveInitiative(i)
        initiatives = try DatabaseService.shared.fetchAllInitiatives()
    }

    func deleteInitiative(id: String) throws {
        try DatabaseService.shared.deleteInitiative(id: id)
        initiatives = try DatabaseService.shared.fetchAllInitiatives()
        try reloadInitiativeAndGoalLinks()
    }

    func saveGoal(_ g: Goal) throws {
        try DatabaseService.shared.saveGoal(g)
        goals = try DatabaseService.shared.fetchAllGoals()
    }

    func deleteGoal(id: String) throws {
        try DatabaseService.shared.deleteGoal(id: id)
        goals = try DatabaseService.shared.fetchAllGoals()
        try reloadInitiativeAndGoalLinks()
    }

    func setMatterInitiatives(matterId: String, ids: Set<String>) throws {
        try DatabaseService.shared.setInitiatives(matterId: matterId, initiativeIds: ids)
        matterInitiativeIds[matterId] = ids
    }

    func setMatterGoals(matterId: String, ids: Set<String>) throws {
        try DatabaseService.shared.setGoals(matterId: matterId, goalIds: ids)
        matterGoalIds[matterId] = ids
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

    // MARK: - 1.3.0 Subtasks

    func reloadSubtaskCounts() throws {
        subtaskCounts = try DatabaseService.shared.fetchSubtaskCounts()
    }

    func addSubtask(matterId: String, body: String) throws {
        let next = (subtasksByMatter[matterId]?.count ?? 0)
        let s = Subtask(id: UUID().uuidString, matterId: matterId, body: body,
                        done: false, sortOrder: next, createdAt: Date())
        try DatabaseService.shared.upsertSubtask(s)
        subtasksByMatter[matterId] = try DatabaseService.shared.fetchSubtasks(matterId: matterId)
        try reloadSubtaskCounts()
    }

    func toggleSubtask(_ s: Subtask) throws {
        var x = s; x.done.toggle()
        try DatabaseService.shared.upsertSubtask(x)
        subtasksByMatter[s.matterId] = try DatabaseService.shared.fetchSubtasks(matterId: s.matterId)
        try reloadSubtaskCounts()
    }

    func updateSubtask(_ s: Subtask) throws {
        try DatabaseService.shared.upsertSubtask(s)
        subtasksByMatter[s.matterId] = try DatabaseService.shared.fetchSubtasks(matterId: s.matterId)
    }

    func deleteSubtask(_ s: Subtask) throws {
        try DatabaseService.shared.deleteSubtask(id: s.id)
        subtasksByMatter[s.matterId] = try DatabaseService.shared.fetchSubtasks(matterId: s.matterId)
        try reloadSubtaskCounts()
    }

    // MARK: - 1.3.0 Linked Matters

    func reloadLinks() throws {
        var byMatter: [String: [MatterLink]] = [:]
        for l in try DatabaseService.shared.fetchAllLinks() {
            byMatter[l.matterId, default: []].append(l)
        }
        linksByMatter = byMatter
    }

    func addLink(from: String, to: String, kind: MatterLink.Kind) throws {
        guard from != to else { return }
        let l = MatterLink(matterId: from, relatedMatterId: to, kind: kind.rawValue)
        try DatabaseService.shared.upsertLink(l)
        try reloadLinks()
    }

    func deleteLink(_ l: MatterLink) throws {
        try DatabaseService.shared.deleteLink(matterId: l.matterId, related: l.relatedMatterId, kind: l.kind)
        try reloadLinks()
    }

    // MARK: - 1.3.0 Trash

    func reloadTrash() throws {
        trashedMatters = try DatabaseService.shared.fetchTrashedMatters()
    }

    // MARK: - 1.3.0 Saved searches

    func reloadSavedSearches() throws {
        savedSearches = try DatabaseService.shared.fetchAllSavedSearches()
    }

    func saveSearch(_ s: SavedSearch) throws {
        try DatabaseService.shared.upsertSavedSearch(s)
        try reloadSavedSearches()
    }

    func deleteSavedSearch(id: String) throws {
        try DatabaseService.shared.deleteSavedSearch(id: id)
        if activeSavedSearchId == id { activeSavedSearchId = nil }
        try reloadSavedSearches()
    }

    // MARK: - 1.3.0 Audit

    /// Apply a SavedSearch criteria block to a Matter list (AND semantics).
    func applySavedSearch(_ c: SearchCriteria, to rows: [Matter]) -> [Matter] {
        var out = rows
        if c.openOnly {
            let terminal = statusValues.last?.name ?? "Closed"
            out = out.filter { $0.status != terminal }
        }
        if !c.typeIds.isEmpty {
            let s = Set(c.typeIds); out = out.filter { s.contains($0.typeId) }
        }
        if !c.statuses.isEmpty {
            let s = Set(c.statuses); out = out.filter { s.contains($0.status) }
        }
        if !c.priorities.isEmpty {
            let s = Set(c.priorities); out = out.filter { s.contains($0.priority) }
        }
        if !c.requestorAssociateIds.isEmpty {
            let s = Set(c.requestorAssociateIds)
            out = out.filter { s.contains($0.requestorAssociateId) }
        }
        if !c.initiativeIds.isEmpty {
            let want = Set(c.initiativeIds)
            out = out.filter { (matterInitiativeIds[$0.id] ?? []).intersection(want).isEmpty == false }
        }
        if !c.goalIds.isEmpty {
            let want = Set(c.goalIds)
            out = out.filter { (matterGoalIds[$0.id] ?? []).intersection(want).isEmpty == false }
        }
        if let n = c.dueWithinDays {
            let cutoff = Calendar.current.date(byAdding: .day, value: n, to: Date()) ?? Date()
            out = out.filter { ($0.dueAt ?? .distantFuture) <= cutoff }
        }
        if let q = c.text, !q.isEmpty {
            let needle = q.lowercased()
            out = out.filter {
                $0.title.lowercased().contains(needle) ||
                $0.id.lowercased().contains(needle)
            }
        }
        return out
    }

    private func emitAuditDeltas(for matterId: String, before: Matter, after: Matter) {
        var events: [AuditEvent] = []
        let now = Date()
        if before.status != after.status {
            events.append(AuditEvent(id: UUID().uuidString, matterId: matterId, ts: now,
                                     kind: "status", beforeValue: before.status, afterValue: after.status))
        }
        if before.priority != after.priority {
            events.append(AuditEvent(id: UUID().uuidString, matterId: matterId, ts: now,
                                     kind: "priority", beforeValue: before.priority, afterValue: after.priority))
        }
        if before.typeId != after.typeId {
            events.append(AuditEvent(id: UUID().uuidString, matterId: matterId, ts: now,
                                     kind: "type", beforeValue: before.typeId, afterValue: after.typeId))
        }
        if before.title != after.title {
            events.append(AuditEvent(id: UUID().uuidString, matterId: matterId, ts: now,
                                     kind: "title", beforeValue: before.title, afterValue: after.title))
        }
        for e in events {
            try? DatabaseService.shared.appendAuditEvent(e)
        }
    }

    // MARK: - 1.4.0 Third Parties (Vendors)

    /// Inclusive year range to render on the Budget & Actuals matrix.
    /// Driven by `AppSettings.thirdPartyYearStart`/`End`. Falls back to a
    /// sensible single-year if the user inverts the range.
    var thirdPartyYearRange: [Int] {
        let s = settingsStore.settings
        let lo = min(s.thirdPartyYearStart, s.thirdPartyYearEnd)
        let hi = max(s.thirdPartyYearStart, s.thirdPartyYearEnd)
        return Array(lo...hi)
    }

    func reloadVendors() throws {
        vendors = try VendorService.fetchAllLive()
        // Drop stale selection if the vendor has been deleted/purged.
        if let sid = selectedVendorId, !vendors.contains(where: { $0.id == sid }) {
            selectedVendorId = nil
            clearVendorSelection()
        }
        if let sid = selectedVendorId {
            try loadSelectedVendor(sid)
        }
    }

    private func clearVendorSelection() {
        vendorContacts = []
        vendorProducts = []
        vendorYearAmounts = []
        vendorInvoices = []
        vendorNotes = []
        vendorEffectiveActuals = [:]
    }

    func selectVendor(id: String?) {
        selectedVendorId = id
        if let id {
            do { try loadSelectedVendor(id) }
            catch { errorMessage = error.localizedDescription }
        } else {
            clearVendorSelection()
        }
    }

    private func loadSelectedVendor(_ id: String) throws {
        vendorContacts = try VendorService.fetchContacts(vendorId: id)
        vendorProducts = try VendorService.fetchProducts(vendorId: id)
        vendorYearAmounts = try VendorService.fetchYearAmounts(vendorId: id)
        vendorInvoices = try VendorInvoiceService.fetchInvoices(vendorId: id)
        vendorNotes = try VendorService.fetchNotes(vendorId: id)
        try recomputeEffectiveActuals(vendorId: id)
    }

    private func recomputeEffectiveActuals(vendorId: String) throws {
        vendorEffectiveActuals = try VendorInvoiceService.effectiveActuals(
            vendorId: vendorId, years: thirdPartyYearRange
        )
    }

    var selectedVendor: Vendor? {
        guard let id = selectedVendorId else { return nil }
        return vendors.first { $0.id == id }
    }

    /// Quick O(1) lookup of vendor-id → vendor for the Matter detail chip.
    var vendorsById: [String: Vendor] {
        Dictionary(uniqueKeysWithValues: vendors.map { ($0.id, $0) })
    }

    @discardableResult
    func createVendor(name: String = "New Vendor") throws -> Vendor {
        let v = Vendor.newDraft(name: name)
        try VendorService.insert(v)
        try reloadVendors()
        selectVendor(id: v.id)
        return v
    }

    func updateVendor(_ v: Vendor) throws {
        try VendorService.update(v)
        try reloadVendors()
    }

    func softDeleteVendor(id: String) throws {
        try VendorService.softDelete(id: id)
        if selectedVendorId == id { selectVendor(id: nil) }
        try reloadVendors()
    }

    // Contacts
    func upsertVendorContact(_ c: VendorContact) throws {
        try VendorService.upsertContact(c)
        if let vid = selectedVendorId {
            vendorContacts = try VendorService.fetchContacts(vendorId: vid)
        }
    }
    func deleteVendorContact(id: String) throws {
        try VendorService.deleteContact(id: id)
        if let vid = selectedVendorId {
            vendorContacts = try VendorService.fetchContacts(vendorId: vid)
        }
    }

    // Products
    func upsertVendorProduct(_ p: VendorProduct) throws {
        try VendorService.upsertProduct(p)
        if let vid = selectedVendorId {
            vendorProducts = try VendorService.fetchProducts(vendorId: vid)
        }
    }
    func deleteVendorProduct(id: String) throws {
        try VendorService.deleteProduct(id: id)
        if let vid = selectedVendorId {
            vendorProducts = try VendorService.fetchProducts(vendorId: vid)
        }
    }

    // Year amounts
    func upsertVendorYearAmount(_ y: VendorYearAmount) throws {
        try VendorService.upsertYearAmount(y)
        if let vid = selectedVendorId {
            vendorYearAmounts = try VendorService.fetchYearAmounts(vendorId: vid)
            try recomputeEffectiveActuals(vendorId: vid)
        }
    }

    // Invoices
    @discardableResult
    func addVendorInvoice(vendorId: String, date: Date, amountCents: Int64,
                          vendorInvoiceNumber: String = "", memo: String = "",
                          fileURL: URL? = nil) throws -> VendorInvoice {
        let inv = try VendorInvoiceService.insert(
            vendorId: vendorId, date: date, amountCents: amountCents,
            vendorInvoiceNumber: vendorInvoiceNumber, memo: memo
        )
        if let fileURL {
            _ = try VendorService.ingestAttachment(
                fileURL: fileURL, vendorId: vendorId,
                kind: .invoice, parentId: inv.id
            )
        }
        if vendorId == selectedVendorId {
            vendorInvoices = try VendorInvoiceService.fetchInvoices(vendorId: vendorId)
            try recomputeEffectiveActuals(vendorId: vendorId)
        }
        return inv
    }

    func updateVendorInvoice(_ inv: VendorInvoice) throws {
        try VendorInvoiceService.update(inv)
        if inv.vendorId == selectedVendorId {
            vendorInvoices = try VendorInvoiceService.fetchInvoices(vendorId: inv.vendorId)
            try recomputeEffectiveActuals(vendorId: inv.vendorId)
        }
    }

    func deleteVendorInvoice(id: String) throws {
        // Capture the vendor first so we can refresh totals; the row is then
        // gone after the cascade.
        let pool = DatabaseService.shared.dbPool
        let vid: String? = try pool.read { db in
            try String.fetchOne(db, sql: "SELECT vendor_id FROM vendor_invoice WHERE id = ?",
                                arguments: [id])
        }
        try VendorInvoiceService.delete(id: id)
        if let vid, vid == selectedVendorId {
            vendorInvoices = try VendorInvoiceService.fetchInvoices(vendorId: vid)
            try recomputeEffectiveActuals(vendorId: vid)
        }
    }

    // Vendor notes
    @discardableResult
    func addVendorNote(vendorId: String, body: String) throws -> VendorNote {
        let now = Date()
        let n = VendorNote(id: UUID().uuidString, vendorId: vendorId,
                           bodyMd: body, createdAt: now, updatedAt: now)
        try VendorService.upsertNote(n)
        if vendorId == selectedVendorId {
            vendorNotes = try VendorService.fetchNotes(vendorId: vendorId)
        }
        return n
    }

    func updateVendorNote(_ n: VendorNote) throws {
        var x = n; x.updatedAt = Date()
        try VendorService.upsertNote(x)
        if x.vendorId == selectedVendorId {
            vendorNotes = try VendorService.fetchNotes(vendorId: x.vendorId)
        }
    }

    func deleteVendorNote(id: String) throws {
        let pool = DatabaseService.shared.dbPool
        let vid: String? = try pool.read { db in
            try String.fetchOne(db, sql: "SELECT vendor_id FROM vendor_note WHERE id = ?",
                                arguments: [id])
        }
        try VendorService.deleteNote(id: id)
        if let vid, vid == selectedVendorId {
            vendorNotes = try VendorService.fetchNotes(vendorId: vid)
        }
    }

    // Vendor attachments
    @discardableResult
    func addVendorAttachment(vendorId: String, fileURL: URL,
                             kind: VendorAttachmentKind,
                             parentId: String? = nil) throws -> VendorAttachment {
        try VendorService.ingestAttachment(
            fileURL: fileURL, vendorId: vendorId, kind: kind, parentId: parentId
        )
    }

    func openVendorAttachment(id: String) throws -> (url: URL, verified: Bool) {
        try VendorService.openAttachment(id: id)
    }

    func deleteVendorAttachment(id: String) throws {
        try VendorService.deleteAttachment(id: id)
    }

    // MARK: - Notes workspace (1.5.0)

    @Published var noteTypes: [NoteType] = []
    @Published var selectedNoteTypeId: String?
    @Published var notesForType: [GenericNote] = []
    @Published var selectedNoteId: String?

    func reloadNoteTypes() throws {
        noteTypes = try NoteTypeService.fetchAll()
        if let id = selectedNoteTypeId, noteTypes.contains(where: { $0.id == id }) == false {
            selectedNoteTypeId = noteTypes.first?.id
        }
        try reloadNotesForSelectedType()
    }

    func reloadNotesForSelectedType() throws {
        guard let id = selectedNoteTypeId else {
            notesForType = []
            selectedNoteId = nil
            return
        }
        notesForType = try GenericNoteService.fetchLive(typeId: id)
        if let sid = selectedNoteId, notesForType.contains(where: { $0.id == sid }) == false {
            selectedNoteId = notesForType.first?.id
        } else if selectedNoteId == nil {
            selectedNoteId = notesForType.first?.id
        }
    }

    func selectNoteType(_ id: String) {
        selectedNoteTypeId = id
        selectedNoteId = nil
        try? reloadNotesForSelectedType()
    }

    // -- Note Type CRUD --

    func addNoteType(name: String) throws -> NoteType {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw NSError(domain: "NoteType", code: 1, userInfo: [NSLocalizedDescriptionKey: "Name required"]) }
        let next = (noteTypes.map { $0.sortOrder }.max() ?? -1) + 1
        let t = NoteType.newDraft(name: trimmed, sortOrder: next)
        try NoteTypeService.insert(t)
        try reloadNoteTypes()
        return t
    }

    func renameNoteType(id: String, to name: String) throws {
        guard var t = noteTypes.first(where: { $0.id == id }) else { return }
        t.name = name.trimmingCharacters(in: .whitespaces)
        try NoteTypeService.update(t)
        try reloadNoteTypes()
    }

    func deleteNoteType(id: String) throws {
        try NoteTypeService.delete(id: id)
        if selectedNoteTypeId == id { selectedNoteTypeId = nil }
        try reloadNoteTypes()
    }

    func reorderNoteTypes(_ ordered: [NoteType]) throws {
        try NoteTypeService.reorder(ordered)
        try reloadNoteTypes()
    }

    // -- Generic Note CRUD --

    @discardableResult
    func addGenericNote(typeId: String, date: Date = Date(), title: String = "") throws -> GenericNote {
        var n = GenericNote.newDraft(typeId: typeId, date: date)
        n.title = title
        try GenericNoteService.insert(n)
        try reloadNotesForSelectedType()
        selectedNoteId = n.id
        return n
    }

    func updateGenericNote(_ n: GenericNote) throws {
        try GenericNoteService.update(n)
        try reloadNotesForSelectedType()
    }

    func deleteGenericNote(id: String) throws {
        try GenericNoteService.softDelete(id: id)
        if selectedNoteId == id { selectedNoteId = nil }
        try reloadNotesForSelectedType()
    }
}
