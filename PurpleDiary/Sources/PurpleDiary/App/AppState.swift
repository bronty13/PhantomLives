import SwiftUI
import Combine
import AppKit

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
    @Published var trackerTags: [TrackerTag] = []
    @Published var trackerValuesByEntry: [String: [Int64: Double]] = [:] // entry.id → (trackerTagId → value)
    @Published var attachmentCountByEntry: [String: Int] = [:]           // entry.id → photo count
    @Published var templates: [Template] = []                            // Phase 5 entry scaffolds

    // MARK: - Journals (Phase 3)

    @Published var journals: [Journal] = []
    @Published var entryCountByJournal: [String: Int] = [:]              // journal.id → entry count
    /// Active journal filter. `nil` = "All journals" (still excludes hidden,
    /// locked journals). A specific id narrows Timeline/Calendar/Search/Insights.
    @Published var selectedJournalId: String? = nil
    /// Hidden journals the user has unlocked for *this session only* (never
    /// persisted — a relaunch re-locks them).
    @Published var unlockedHiddenJournalIds: Set<String> = []

    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    @Published var selectedSection: Section = .timeline
    @Published var selectedEntryId: String?
    @Published var searchQuery: String = ""

    // MARK: - Privacy / lock

    /// Owns the data-encryption key. Constructed against the support dir so its
    /// keystore.json / recovery_envelope.json / Keychain slot all scope to this
    /// install. `refreshState()` in its init attempts a silent Keychain unlock.
    @Published var keyStore = KeyStore(supportDirectoryURL: DatabaseService.supportDirectory)

    /// When true, `ContentView` swaps the main UI for the lock screen until the
    /// user re-authenticates. Runtime-only — never persisted.
    @Published var appLocked: Bool = false

    /// First-launch (or recovery-envelope migration) hands the user a 24-word
    /// recovery phrase that must be shown and confirmed-saved before the app is
    /// usable. `ContentView` presents the save-recovery-key sheet while set.
    @Published var pendingRecoveryKey: [String]? = nil

    /// Non-nil when the on-disk DB is encrypted with a key we no longer have.
    /// `ContentView` shows the recovery screen (enter recovery key / reset).
    @Published var dbUnrecoverable: String? = nil

    private var lockObserver: NSObjectProtocol?

    // MARK: - Sections (sidebar top-level)

    enum Section: String, Hashable, CaseIterable {
        case timeline
        case calendar
        case onThisDay
        case insights
        case search
        case people
        case tags
        case trackers

        var title: String {
            switch self {
            case .timeline:  return "Timeline"
            case .calendar:  return "Calendar"
            case .onThisDay: return "On This Day"
            case .insights:  return "Insights"
            case .search:    return "Search"
            case .people:    return "People"
            case .tags:      return "Tags"
            case .trackers:  return "Trackers"
            }
        }

        var systemImage: String {
            switch self {
            case .timeline:  return "list.bullet.rectangle"
            case .calendar:  return "calendar"
            case .onThisDay: return "clock.arrow.circlepath"
            case .insights:  return "chart.line.uptrend.xyaxis"
            case .search:    return "magnifyingglass"
            case .people:    return "person.2.fill"
            case .tags:      return "tag.fill"
            case .trackers:  return "chart.xyaxis.line"
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
        // 1. Ensure settings.json exists so the launch backup never archives an
        //    empty support directory.
        settingsStore.save()

        // 2. Route the SQLCipher pool at the live keystore *before* any DB
        //    access, so the first open is keyed. The closure re-resolves on
        //    every connection, so it survives keystore swaps (recovery/reset).
        DatabaseService.keyResolver = { [weak keyStore] in keyStore?.currentKey }

        // 3. First-run bootstrap: generate the DEK + 24-word recovery phrase.
        //    (No-op for returning installs, which silent-unlock via Keychain in
        //    KeyStore.init.) Probed via the static helper so we don't build the
        //    DatabaseService singleton — and trigger its migration — before the
        //    launch backup below has captured the pre-migration state.
        bootstrapKeystoreIfNeeded()

        // 4. Auto-backup-on-launch — runs BEFORE the SQLCipher migration so an
        //    upgrade install's plaintext diary.sqlite is captured as a safety
        //    net, and the fresh keystore/recovery files are backed up too.
        //    Errors are logged, never thrown.
        BackupService.runOnLaunchIfDue(settingsStore: settingsStore)

        // 5. Build/open the DB. With a key in scope the singleton's init
        //    migrates an existing plaintext file to SQLCipher and opens keyed; a
        //    fresh install gets a new encrypted DB. Then confirm the keyed pool
        //    is actually live (else surface the recovery screen).
        _ = DatabaseService.shared
        openKeyedDatabaseAndCheckHealth()

        // 6. Record the ever-booted marker (anti-data-loss guard) and backfill a
        //    recovery envelope for any pre-existing unlocked keystore.
        markBootedAndMigrateRecoveryEnvelope()

        // 7. Normal startup.
        try? DatabaseService.shared.seedDefaultTagsIfEmpty()
        try? DatabaseService.shared.seedDefaultTemplatesIfEmpty()
        reloadAll()
        let didInstall = SampleDataService.installIfFirstRunCompleted(
            existing: entries, settingsStore: settingsStore
        )
        if didInstall { reloadAll() }

        // 8. Engage the lock screen on launch if the user enabled it.
        if settings.lockEnabled && settings.lockOnLaunch && dbUnrecoverable == nil {
            appLocked = true
        }

        // 9. Lock when the app loses focus, if app-lock is enabled.
        installLockOnBackgroundObserver()

        // 10. Keep the daily reminder (if the user enabled it) in sync with the
        //     OS each launch. Never prompts here — authorization is requested
        //     only when the user turns the reminder on in Settings.
        updateReminderSchedule()
    }

    /// Re-register the single daily reminder from current settings.
    func updateReminderSchedule() {
        NotificationService.reschedule(enabled: settings.reminderEnabled,
                                       hour: settings.reminderHour,
                                       minute: settings.reminderMinute)
    }

    deinit {
        if let lockObserver { NotificationCenter.default.removeObserver(lockObserver) }
    }

    // MARK: - Reload

    func reloadAll() {
        isLoading = true
        do {
            entries = try DatabaseService.shared.fetchAllEntries()
            tags    = try DatabaseService.shared.fetchAllTags()
            people  = try DatabaseService.shared.fetchAllPeople()
            trackerTags = try DatabaseService.shared.fetchAllTrackerTags()
            journals = try DatabaseService.shared.fetchAllJournals()
            entryCountByJournal = try DatabaseService.shared.entryCountByJournal()
            templates = try DatabaseService.shared.fetchAllTemplates()
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
            entryCountByJournal = try DatabaseService.shared.entryCountByJournal()
            try reloadJoins()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadJournals() {
        do {
            journals = try DatabaseService.shared.fetchAllJournals()
            entryCountByJournal = try DatabaseService.shared.entryCountByJournal()
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
        trackerValuesByEntry = try DatabaseService.shared.trackerValuesByEntry()
        attachmentCountByEntry = try DatabaseService.shared.attachmentCountByEntry()
    }

    func reloadTrackers() {
        do {
            trackerTags = try DatabaseService.shared.fetchAllTrackerTags()
            try reloadJoins()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Selection helpers

    var selectedEntry: Entry? {
        guard let id = selectedEntryId else { return nil }
        return entries.first { $0.id == id }
    }

    // MARK: - Journals: visibility

    var journalsById: [String: Journal] {
        Dictionary(uniqueKeysWithValues: journals.map { ($0.id, $0) })
    }

    /// Journals that should appear in the sidebar's switcher and be selectable:
    /// non-hidden journals plus any hidden ones unlocked this session.
    var visibleJournals: [Journal] {
        journals.filter { !$0.isHidden || unlockedHiddenJournalIds.contains($0.id) }
    }

    var hasHiddenJournals: Bool { journals.contains { $0.isHidden } }

    /// Pure visibility rule, factored out for testing. An entry is shown when:
    /// its journal isn't hidden (or has been unlocked this session), AND its
    /// journal isn't a *locked* vault (a vault is opaque until its content key
    /// is in the session), AND it matches the active journal filter (`nil`
    /// selection = all accessible journals).
    static func entryIsVisible(entryJournalId: String,
                               selectedJournalId: String?,
                               journalIsHidden: Bool,
                               journalIsUnlocked: Bool,
                               journalIsVault: Bool = false,
                               vaultIsUnlocked: Bool = false) -> Bool {
        if journalIsHidden && !journalIsUnlocked { return false }
        if journalIsVault && !vaultIsUnlocked { return false }
        if let sel = selectedJournalId, sel != entryJournalId { return false }
        return true
    }

    /// Entries the Timeline / Calendar / Search / Insights should operate on,
    /// after applying the hidden-journal gate, the locked-vault gate, and the
    /// active journal filter.
    var visibleEntries: [Entry] {
        entries.filter { entry in
            let journal = journalsById[entry.journalId]
            let hidden = journal?.isHidden ?? false
            let vault = journal?.isVault ?? false
            return Self.entryIsVisible(
                entryJournalId: entry.journalId,
                selectedJournalId: selectedJournalId,
                journalIsHidden: hidden,
                journalIsUnlocked: unlockedHiddenJournalIds.contains(entry.journalId),
                journalIsVault: vault,
                vaultIsUnlocked: VaultService.isUnlocked(entry.journalId)
            )
        }
    }

    // MARK: - Journals: mutations

    @discardableResult
    func createJournal(name: String, colorHex: String = "#7C5CFF", symbol: String = "book.closed") throws -> Journal {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let journal = Journal.newDraft(name: trimmed.isEmpty ? "Untitled" : trimmed,
                                       colorHex: colorHex, symbol: symbol,
                                       sortOrder: (journals.map(\.sortOrder).max() ?? 0) + 1)
        try DatabaseService.shared.insertJournal(journal)
        reloadJournals()
        return journal
    }

    func updateJournal(_ journal: Journal) throws {
        try DatabaseService.shared.updateJournal(journal)
        reloadJournals()
    }

    func setJournalHidden(_ hidden: Bool, journalId: String) throws {
        guard var j = journalsById[journalId] else { return }
        j.isHidden = hidden
        try DatabaseService.shared.updateJournal(j)
        if hidden {
            unlockedHiddenJournalIds.remove(journalId)
            if selectedJournalId == journalId { selectedJournalId = nil }
        }
        reloadJournals()
    }

    func deleteJournal(id: String, deleteEntries: Bool = false) throws {
        guard id != Journal.defaultId else { return }
        try DatabaseService.shared.deleteJournal(id: id, deleteEntries: deleteEntries)
        if selectedJournalId == id { selectedJournalId = nil }
        unlockedHiddenJournalIds.remove(id)
        if selectedEntryId != nil && entries.first(where: { $0.id == selectedEntryId }) == nil {
            selectedEntryId = nil
        }
        reloadJournals()
        reloadEntries()   // entries were reassigned to (or removed with) the journal
    }

    /// Move a single entry into another journal.
    func setEntryJournal(_ journalId: String, entryId: String) throws {
        try DatabaseService.shared.setJournal(journalId, forEntry: entryId)
        reloadEntries()
    }

    // MARK: - Vault (Phase 9)

    func isVaultUnlocked(_ journalId: String) -> Bool { VaultService.isUnlocked(journalId) }

    /// Convert a journal into a vault: create + verify the dual-wrapped envelope,
    /// flag the journal, then seal its existing entries. The flag is set *before*
    /// sealing so a mid-way failure leaves readable plaintext-in-a-vault (which
    /// the next edit / a re-run re-seals) rather than orphaned ciphertext.
    func makeVault(journalId: String, passphrase: String, recoveryWords: [String]) throws {
        let ck = try VaultService.createVault(journalId: journalId, passphrase: passphrase,
                                              recoveryWords: recoveryWords)
        try DatabaseService.shared.setJournalVault(true, journalId: journalId)
        try DatabaseService.shared.sealEntries(inJournal: journalId, using: ck)
        try DatabaseService.shared.rekeyAttachments(inJournal: journalId, key: ck, seal: true)
        reloadJournals()
        reloadEntries()
    }

    /// Unlock a vault for the session via its passphrase. On success the journal
    /// and its entries become visible again.
    @discardableResult
    func unlockVault(journalId: String, passphrase: String) -> Bool {
        let ok = VaultService.unlock(journalId: journalId, passphrase: passphrase)
        if ok { reloadEntries() }
        return ok
    }

    /// Unlock a vault via the 24-word recovery key (forgot-passphrase path).
    @discardableResult
    func unlockVault(journalId: String, recoveryWords: [String]) -> Bool {
        let ok = VaultService.unlock(journalId: journalId, recoveryWords: recoveryWords)
        if ok { reloadEntries() }
        return ok
    }

    /// Re-lock a vault: drop its session key and re-gate it. Clears the filter
    /// selection if it pointed at this journal.
    func lockVault(journalId: String) {
        VaultService.lock(journalId)
        if selectedJournalId == journalId { selectedJournalId = nil }
        reloadEntries()
    }

    func changeVaultPassphrase(journalId: String, newPassphrase: String) throws {
        try VaultService.changePassphrase(journalId: journalId, newPassphrase: newPassphrase)
    }

    /// Remove a vault: decrypt its entries back to plaintext, drop the flag and
    /// the envelope. Requires the vault to be unlocked (key in the session).
    func removeVault(journalId: String) throws {
        guard let ck = VaultService.key(for: journalId) else { throw VaultService.VaultError.locked }
        try DatabaseService.shared.unsealEntries(inJournal: journalId, using: ck)
        try DatabaseService.shared.rekeyAttachments(inJournal: journalId, key: ck, seal: false)
        try DatabaseService.shared.setJournalVault(false, journalId: journalId)
        try DatabaseService.shared.deleteVaultEnvelope(journalId: journalId)
        VaultService.lock(journalId)
        reloadJournals()
        reloadEntries()
    }

    /// Unlock a hidden journal for this session via the app-lock gate (Touch ID /
    /// device password / passphrase). On success the journal becomes selectable
    /// and its entries appear. No-op for non-hidden journals.
    func unlockHiddenJournal(_ journalId: String) async {
        guard let j = journalsById[journalId], j.isHidden else { return }
        if unlockedHiddenJournalIds.contains(journalId) { return }
        let result = await BiometricAuthService.authenticate(
            reason: "unlock the “\(j.name)” journal",
            biometryOnly: settings.biometryOnlyMode
        )
        if result == .success {
            unlockedHiddenJournalIds.insert(journalId)
        } else if case .unavailable = result {
            // No biometrics/passcode on this Mac — reveal rather than lock the
            // user out of their own data (app-lock has the same fallback).
            unlockedHiddenJournalIds.insert(journalId)
        }
    }

    // MARK: - Entry mutations

    @discardableResult
    func createEntry(date: Date = Date(), title: String = "") throws -> Entry {
        // New entries land in the active journal (or the default when "All" is
        // selected). A hidden journal is only selectable once unlocked, so this
        // never silently writes into a locked journal.
        let journalId = selectedJournalId ?? Journal.defaultId
        let entry = Entry.newDraft(date: date, title: title, journalId: journalId)
        try DatabaseService.shared.insertEntry(entry)
        reloadEntries()
        selectedEntryId = entry.id
        return entry
    }

    /// Create a new entry pre-filled from a template (date/time tokens rendered).
    @discardableResult
    func createEntry(fromTemplate template: Template, date: Date = Date()) throws -> Entry {
        let journalId = selectedJournalId ?? Journal.defaultId
        var entry = Entry.newDraft(date: date, journalId: journalId)
        entry.bodyMarkdown = TemplateService.render(template.body, date: date)
        try DatabaseService.shared.insertEntry(entry)
        reloadEntries()
        selectedEntryId = entry.id
        return entry
    }

    func updateEntry(_ entry: Entry) throws {
        try DatabaseService.shared.updateEntry(entry)
        reloadEntries()
    }

    // MARK: - Template mutations

    func reloadTemplates() {
        templates = (try? DatabaseService.shared.fetchAllTemplates()) ?? templates
    }

    @discardableResult
    func createTemplate(name: String, body: String) throws -> Template {
        let t = Template.newDraft(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                  body: body,
                                  sortOrder: (templates.map(\.sortOrder).max() ?? 0) + 1)
        try DatabaseService.shared.insertTemplate(t)
        reloadTemplates()
        return t
    }

    func updateTemplate(_ template: Template) throws {
        try DatabaseService.shared.updateTemplate(template)
        reloadTemplates()
    }

    func deleteTemplate(id: String) throws {
        try DatabaseService.shared.deleteTemplate(id: id)
        reloadTemplates()
    }

    func deleteEntry(id: String) throws {
        try DatabaseService.shared.deleteEntry(id: id)
        if selectedEntryId == id { selectedEntryId = nil }
        reloadEntries()
        if selectedEntryId == nil { selectedEntryId = entries.first?.id }
    }

    /// True when an entry carries *no information at all*: blank title and body,
    /// no mood, no tags, no logged trackers, and no attachments. Used to silently
    /// discard a new entry the user opened but never filled in. The bar is
    /// deliberately strict (everything empty) so we never drop an entry that has
    /// any content — e.g. a photo or a mood with no text.
    static func entryIsEmpty(title: String, body: String, mood: Mood,
                             tagCount: Int, trackerCount: Int, attachmentCount: Int) -> Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && mood == .unset
            && tagCount == 0
            && trackerCount == 0
            && attachmentCount == 0
    }

    /// Delete `entryId` iff it is completely empty per `entryIsEmpty`, combining
    /// the (possibly still-unsaved) editor fields with the persisted tags /
    /// tracker values / attachments. Returns true if it was discarded. This is
    /// the zero-friction "don't keep blank entries" path — no confirmation
    /// prompt, because there's nothing to lose.
    @discardableResult
    func discardEntryIfEmpty(_ entryId: String, title: String, body: String, mood: Mood) -> Bool {
        let tagCount = (try? DatabaseService.shared.tagIDs(forEntry: entryId).count) ?? 0
        let trackerCount = (try? DatabaseService.shared.trackerValues(forEntry: entryId).count) ?? 0
        let attachmentCount = (try? DatabaseService.shared.attachmentThumbs(forEntry: entryId).count) ?? 0
        guard Self.entryIsEmpty(title: title, body: body, mood: mood,
                                tagCount: tagCount, trackerCount: trackerCount,
                                attachmentCount: attachmentCount) else { return false }
        try? deleteEntry(id: entryId)
        return true
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

    // MARK: - Tracker mutations

    func saveTrackerTag(_ tracker: TrackerTag) throws {
        var mutable = tracker
        try DatabaseService.shared.saveTrackerTag(&mutable)
        reloadTrackers()
    }

    func deleteTrackerTag(id: Int64) throws {
        try DatabaseService.shared.deleteTrackerTag(id: id)
        reloadTrackers()
    }

    /// Log (value != nil) or clear (nil) a tracker's value on an entry.
    func setTrackerValue(_ value: Double?, trackerTagId: Int64, forEntry entryId: String) throws {
        try DatabaseService.shared.setTrackerValue(value, trackerTagId: trackerTagId, forEntry: entryId)
        try reloadJoins()
    }

    // MARK: - Attachment mutations

    func addAttachment(_ attachment: Attachment) throws {
        try DatabaseService.shared.insertAttachment(attachment)
        refreshAttachmentCounts()
    }

    func deleteAttachment(id: String) throws {
        try DatabaseService.shared.deleteAttachment(id: id)
        refreshAttachmentCounts()
    }

    private func refreshAttachmentCounts() {
        attachmentCountByEntry = (try? DatabaseService.shared.attachmentCountByEntry()) ?? attachmentCountByEntry
    }

    // MARK: - Keystore bootstrap (launch)

    /// First-run: generate a DEK (+ 24-word recovery phrase) when no keystore
    /// exists yet. No-op for returning installs (silent-unlocked in
    /// KeyStore.init) and under XCTest. The error cases route to the recovery
    /// screen rather than silently minting a key that can't decrypt existing
    /// data.
    private func bootstrapKeystoreIfNeeded() {
        guard keyStore.state == .notSetup,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        else { return }
        // If encrypted data already exists on disk but we're about to mint a
        // fresh DEK, that DEK can't decrypt it — surface recovery instead.
        let dbLooksEncrypted = DatabaseService.databaseFileLooksEncrypted()
        do {
            pendingRecoveryKey = try keyStore.setupKeychainManaged()
            if dbLooksEncrypted {
                dbUnrecoverable = "PurpleDiary found encrypted data on disk but no key to unlock it. "
                    + "The Keychain entry may have been removed. Enter your 24-word recovery key to "
                    + "unlock it, or reset to start fresh."
            }
        } catch KeyStore.KeyStoreError.everBootedButKeychainGone {
            NSLog("PurpleDiary: ever-booted marker present but Keychain entry gone — refusing to mint a fresh DEK.")
            dbUnrecoverable = "PurpleDiary has run on this Mac before, but the Keychain entry that "
                + "unlocks your diary is gone. Enter your 24-word recovery key below, or reset to start "
                + "fresh. (Your encrypted data is preserved on disk in case the key can be recovered.)"
        } catch KeyStore.KeyStoreError.keychainEntryAlreadyExists {
            NSLog("PurpleDiary: Keychain entry present but unreadable — refusing to overwrite.")
            dbUnrecoverable = "PurpleDiary's Keychain entry exists but can't be read right now (usually "
                + "transient). Quit and try again; if it persists, enter your recovery key or reset."
        } catch {
            NSLog("PurpleDiary: keystore setup failed — \(error.localizedDescription)")
        }
    }

    /// Reopen the SQLCipher pool under the live DEK and detect the broken state
    /// where the on-disk file can't be opened with the available key.
    private func openKeyedDatabaseAndCheckHealth() {
        guard keyStore.currentKey != nil else { return }
        do {
            try DatabaseService.shared.reopenDatabase()
        } catch {
            NSLog("PurpleDiary: SQLCipher reopen failed — \(error.localizedDescription)")
        }
        if DatabaseService.shared.isUsingPlaceholderPool && dbUnrecoverable == nil {
            dbUnrecoverable = "Your diary is encrypted with a key that's no longer in this Mac's "
                + "Keychain. Enter your 24-word recovery key to unlock it, or reset to start fresh."
        }
    }

    /// Mark this install ever-booted (so a future Keychain loss is treated as
    /// recoverable, not a fresh install) and backfill a recovery envelope for a
    /// pre-existing unlocked keystore that predates recovery keys.
    private func markBootedAndMigrateRecoveryEnvelope() {
        guard keyStore.state == .unlocked,
              dbUnrecoverable == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        else { return }
        BootState.markBooted(in: DatabaseService.supportDirectory)
        if pendingRecoveryKey == nil, let migrated = try? keyStore.ensureRecoveryEnvelope() {
            pendingRecoveryKey = migrated
        }
    }

    // MARK: - App-wide lock

    private func installLockOnBackgroundObserver() {
        lockObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Lock when the app loses focus, but only if the user enabled
                // app-lock and the lock screen isn't already up.
                if self.settings.lockEnabled, !self.appLocked, self.dbUnrecoverable == nil {
                    self.lockApp()
                }
            }
        }
    }

    /// Lock the application: drop every vault session key (so the lock screen
    /// truly re-seals vaults), wipe the in-memory DEK when a passphrase is set
    /// (so a memory snapshot can't reveal it), and show the lock screen.
    func lockApp() {
        VaultService.lockAll()
        unlockedHiddenJournalIds.removeAll()
        if keyStore.hasPassphrase { _ = keyStore.lock() }
        appLocked = true
    }

    /// Clear the lock screen after a successful Touch ID / device-password
    /// challenge. When a passphrase wiped the DEK, the keystore is re-unlocked
    /// separately (biometric path re-reads the Keychain via reopen).
    func unlockApp() {
        appLocked = false
    }

    /// Touch ID / device-password unlock from the lock screen. On success,
    /// re-reads the keystore (the Keychain DEK survives `lock()` only when no
    /// passphrase is set; with a passphrase the user must use that path) and
    /// reopens the DB if needed.
    func attemptBiometricUnlock() async -> Bool {
        let result = await BiometricAuthService.authenticate(
            reason: "unlock your diary",
            biometryOnly: settings.biometryOnlyMode
        )
        guard case .success = result else { return false }
        // Keychain-managed installs keep the DEK across the screen lock, so just
        // dropping the screen is enough. Passphrase installs had their DEK
        // wiped; biometrics alone can't recover it — but a refreshState picks up
        // the Keychain cache that `unlock(passphrase:)` re-seeds, so try it.
        keyStore.refreshState()
        if keyStore.currentKey != nil, DatabaseService.shared.isUsingPlaceholderPool {
            try? DatabaseService.shared.reopenDatabase()
        }
        unlockApp()
        return true
    }

    /// Unlock the keystore with the user's passphrase from the lock screen.
    @discardableResult
    func unlockWithPassphrase(_ passphrase: String) -> Bool {
        do {
            try keyStore.unlock(passphrase: passphrase)
            if DatabaseService.shared.isUsingPlaceholderPool {
                try DatabaseService.shared.reopenDatabase()
            }
            unlockApp()
            reloadAll()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Recovery

    /// User confirmed they saved their recovery key — dismiss the gating sheet.
    func confirmRecoveryKeySaved() {
        pendingRecoveryKey = nil
    }

    /// Recovery screen "Enter recovery key" path. Unlocks the keystore from the
    /// 24-word phrase, reopens the DB, and clears the unrecoverable state.
    @discardableResult
    func tryRecoveryKeyUnlock(phrase: String) -> Result<Void, Error> {
        do {
            _ = try RecoveryKey.entropy(from: phrase)   // surface typos as a specific error
            try keyStore.unlockWithRecoveryKey(phrase: phrase)
            try DatabaseService.shared.reopenDatabase()
            if DatabaseService.shared.isUsingPlaceholderPool {
                return .failure(KeyStore.KeyStoreError.corrupt)
            }
            BootState.markBooted(in: DatabaseService.supportDirectory)
            dbUnrecoverable = nil
            reloadAll()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    /// Recovery screen "Reset and start fresh" path. Quarantines the unreadable
    /// DB, wipes the keystore, mints a new DEK + recovery key, and opens a fresh
    /// encrypted DB. The old data is preserved in a `.unrecoverable-…/` folder.
    func resetUnrecoverableData() {
        do {
            try DatabaseService.shared.quarantineDatabaseFiles()
            keyStore.resetAndWipe()
            pendingRecoveryKey = try keyStore.setupKeychainManaged()
            try DatabaseService.shared.reopenDatabase()
            try? DatabaseService.shared.seedDefaultTagsIfEmpty()
            dbUnrecoverable = nil
            settingsStore.load()
            reloadAll()
        } catch {
            NSLog("PurpleDiary: recovery reset failed — \(error.localizedDescription)")
            dbUnrecoverable = "Recovery reset failed: \(error.localizedDescription)"
        }
    }
}
