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
        case insights
        case search
        case people
        case tags
        case trackers

        var title: String {
            switch self {
            case .timeline: return "Timeline"
            case .calendar: return "Calendar"
            case .insights: return "Insights"
            case .search:   return "Search"
            case .people:   return "People"
            case .tags:     return "Tags"
            case .trackers: return "Trackers"
            }
        }

        var systemImage: String {
            switch self {
            case .timeline: return "list.bullet.rectangle"
            case .calendar: return "calendar"
            case .insights: return "chart.line.uptrend.xyaxis"
            case .search:   return "magnifyingglass"
            case .people:   return "person.2.fill"
            case .tags:     return "tag.fill"
            case .trackers: return "chart.xyaxis.line"
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
        trackerValuesByEntry = try DatabaseService.shared.trackerValuesByEntry()
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

    /// Lock the application: wipe the in-memory DEK when a passphrase is set
    /// (so a memory snapshot can't reveal it) and show the lock screen.
    func lockApp() {
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
