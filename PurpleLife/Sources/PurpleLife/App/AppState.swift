import Foundation
import SwiftUI
import Combine

/// Top-level observable state. Phase 1 keeps it deliberately thin: it owns
/// the SettingsStore, fires the launch-time backup before any UI reads the
/// DB, and exposes the singleton `DatabaseService` to views.
@MainActor
final class AppState: ObservableObject {

    /// Notification posted when the user invokes the ⌘N "New record"
    /// menu command. `RecordsScreen` observes and creates a new record
    /// of its currently-displayed type.
    static let newRecordRequestedNotification = Notification.Name("PurpleLife.newRecordRequested")

    /// Notification posted when the user invokes a ⌘1…⌘9 "Jump to
    /// type" command. `userInfo["index"]` carries the 1-based position
    /// in `SchemaRegistry.visibleTypes`.
    static let jumpToTypeIndexNotification = Notification.Name("PurpleLife.jumpToTypeIndex")

    /// Posted when CloudKit pulls in remote object changes so the UI
    /// can refresh its `@State`-cached row lists. Without this, Mac B
    /// receives a record into the local DB but the visible
    /// `RecordsScreen` doesn't reload until the user switches types
    /// or restarts the app — defeats the point of real-time sync.
    /// `AppState` listens and calls `reloadAll()`; `RecordsScreen`
    /// listens and calls its own `reload()`.
    static let objectsChangedRemotelyNotification = Notification.Name("PurpleLife.objectsChangedRemotely")
    @Published var settingsStore = SettingsStore()
    @Published var schema = SchemaRegistry()
    @Published var sync = CloudKitSyncService()
    @Published var keyStore = KeyStore(supportDirectoryURL: DatabaseService.supportDirectory)
    let database = DatabaseService.shared

    @Published var objectCount: Int = 0

    /// Health of the on-disk database. Set after the launch-time keyed
    /// reopen attempt: `.ok` is the normal path, `.unrecoverable` means
    /// the file is encrypted with a key we no longer have (Keychain
    /// entry cleared while the file stayed encrypted — the symptom is
    /// a string of "no such table: objects" errors against the
    /// placeholder pool). `ContentView` swaps to `RecoveryScreen`
    /// when `.unrecoverable`.
    @Published var dbHealth: DBHealth = .ok

    enum DBHealth: Equatable {
        case ok
        /// The string is the underlying error description, surfaced to
        /// the user in the recovery sheet so they can decide whether to
        /// reset or to copy the message and investigate first.
        case unrecoverable(String)
    }

    /// Sidebar selection. The special value `nil` means "Today" (the
    /// home panel that doesn't belong to any type). Real type ids
    /// select that type's records pane.
    @Published var selectedTypeId: String?
    @Published var showTodayInDetail: Bool = true

    /// Set by the Quick Switcher to ask the main window to open a
    /// specific record. The `RecordsScreen` watches this and routes it
    /// into its detail sheet, then clears it.
    @Published var openRecordRequest: String?

    /// Combine subscriptions held for the lifetime of the AppState.
    /// Currently bridges `SettingsStore.objectWillChange` into our own
    /// `objectWillChange` so a settings mutation (theme switch,
    /// appearance change, etc.) re-renders every view observing
    /// AppState. Without this, mutating a nested `@Published` on a
    /// nested ObservableObject doesn't propagate up.
    private var cancellables: Set<AnyCancellable> = []

    /// Pass-through to the underlying SettingsStore — saves on every set.
    /// Lets views write `appState.settings.foo = …` without thinking about
    /// the store. Mirrors the Timeliner pattern.
    var settings: AppSettings {
        get { settingsStore.settings }
        set {
            settingsStore.settings = newValue
            settingsStore.save()
        }
    }

    init() {
        // Force-load SQLCipher's static archive into the binary. Without
        // this reference, the linker resolves `sqlite3_*` to the system
        // libsqlite3.dylib and our vendored SQLCipher is dead weight.
        _ = SQLCipherForceLink._force

        // First-launch keystore bootstrap: if no DEK exists yet, generate
        // one and stash it in the Keychain. The user can later add a
        // passphrase via Settings → Security. Doing this before any
        // persistence path runs means future slices (SQLCipher DB,
        // encrypted attachments, encrypted settings) always have a DEK
        // available. Skipped under XCTest so the unit tests use their own
        // per-test KeyStores via tempDir.
        if keyStore.state == .notSetup,
           ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            do {
                try keyStore.setupKeychainManaged()
            } catch {
                NSLog("PurpleLife: keystore setup failed — \(error.localizedDescription)")
            }
        }

        // Wire the SettingsStore to the live keystore. The store was
        // constructed without a key (property initializer can't reference
        // self.keyStore), so any settings.json read above happened with
        // `keyResolver: { nil }` — that's OK because (a) a freshly
        // installed app has no settings.json yet, and (b) an upgrade
        // install where settings.json is plaintext also reads fine with
        // nil key. With the resolver pointed at the live keystore now,
        // the next `save()` writes encrypted bytes.
        settingsStore.setKeyResolver { [weak keyStore] in
            keyStore?.currentKey
        }
        // Same wiring for the attachments enum-of-statics. Setting it
        // here (and only here) keeps the dependency injection one-way:
        // AppState owns the keystore, services read from it.
        AttachmentService.keyResolver = { [weak keyStore] in
            keyStore?.currentKey
        }
        // Whole-database SQLCipher encryption (slice A2). DatabaseService
        // was constructed during property init with no key — so the
        // initial pool is plaintext. Wiring the resolver here lets us
        // (a) detect a plaintext file on disk and migrate it to
        // SQLCipher via `sqlcipher_export()`, and (b) reopen the pool
        // with `PRAGMA key` applied so every subsequent connection is
        // keyed. Idempotent: after the first migration the file is no
        // longer plaintext, the magic-header check skips, only the
        // reopen-with-key step runs.
        DatabaseService.keyResolver = { [weak keyStore] in
            keyStore?.currentKey
        }
        if keyStore.currentKey != nil {
            do {
                try database.reopenDatabase()
            } catch {
                NSLog("PurpleLife: SQLCipher reopen failed — \(error.localizedDescription)")
            }
            // After the reopen attempt, the placeholder flag tells us
            // whether the keyed pool is actually live or whether we're
            // still on the temp placeholder. The latter means every
            // query in the rest of the app will fail; surface the
            // recovery UX instead of letting the user click into a
            // broken sidebar.
            if database.isUsingPlaceholderPool {
                dbHealth = .unrecoverable(
                    "The on-disk database is encrypted with a key that's no longer in the Keychain. " +
                    "This usually means the Keychain entry was cleared while the file stayed encrypted."
                )
            }
        }
        // Re-read settings.json once the resolver is live so a previously-
        // encrypted file (from a prior launch where slice A3 was active)
        // decrypts correctly. No-op for plaintext / missing files.
        settingsStore.load()
        // Idempotent encrypt-on-upgrade: forces a save with the live key
        // resolver so a plaintext settings.json written during the early
        // (resolver-less) seedTodayQueriesIfNeeded call gets sealed before
        // anything else runs. If the file is already encrypted, this is a
        // no-cost re-encrypt-with-the-same-key.
        if keyStore.currentKey != nil {
            settingsStore.save()
            // Same sweep for any plaintext attachment files lingering from
            // a pre-A3 install. Idempotent — files already wrapped get
            // skipped by the magic-header check.
            AttachmentService.encryptExistingFilesIfNeeded()
            // Note: per-row field_json encryption (the A2′ stand-in) is
            // intentionally NOT swept here anymore. Slice A2's SQLCipher
            // page-level encryption supersedes it; calling the column-
            // level sweep on top of SQLCipher would double-wrap new
            // writes for no benefit. Existing column-wrapped rows from
            // the A2′-only window still read back correctly through
            // `unsealFromStorage` in `DatabaseService.fetch*`.
        }

        // Backup-on-launch must run BEFORE any code touches the DB pool, so
        // the archive captures a clean copy of the on-disk state from the
        // last session. BackupService swallows its own errors.
        BackupService.runOnLaunchIfDue(settingsStore: settingsStore)

        // Push the persisted theme into the static facade BEFORE any view
        // body runs. SwiftUI evaluates @StateObject inits eagerly, so by
        // the time WindowGroup renders the active palette is already in
        // place — no first-frame flash of the default.
        Theme.current = settingsStore.currentTheme

        // Bridge SettingsStore's @Published changes up to AppState's
        // observers. The pass-through `appState.settings = …` setter
        // mutates settingsStore.settings, which fires SettingsStore's
        // objectWillChange but NOT AppState's; without this Combine
        // hop, views observing AppState wouldn't re-render after a
        // theme switch or appearance change.
        settingsStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                // Re-resolve the active theme on every settings change
                // so views reading `Theme.bg` see the new palette on
                // their next body evaluation.
                Theme.current = self.settingsStore.currentTheme
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Same bridge for SchemaRegistry. Without it, `@Published var
        // schema` only fires when the SchemaRegistry instance itself
        // gets reassigned — internal `types` / `hiddenBuiltInIds`
        // mutations bubble through `schema.objectWillChange` but never
        // reach `AppState.objectWillChange`. Symptom: SchemaEditor's
        // "Delete field" / "Move up" / "Move down" buttons mutate the
        // model correctly but the rendered field list doesn't refresh
        // until the user clicks away and back (which forces a new
        // body evaluation).
        schema.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Same nested-ObservableObject bridge for KeyStore. Symptoms
        // without it: Settings → Security tab doesn't reflect Lock /
        // Unlock state transitions until you click another tab and
        // come back. Same fix as the schema bridge above.
        keyStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Same for CloudKitSyncService. Symptoms: the sync footer
        // stays at "Synced" even when the service transitions to
        // .error or .syncing, since the surrounding view observes
        // AppState rather than `sync` directly.
        sync.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Wire ObjectEngine → SchemaRegistry so search-index updates have
        // the type definitions they need.
        ObjectEngine.currentSchema = schema
        ObjectEngine.sync = sync
        // Wire SchemaRegistry → sync so user schema mutations
        // (add/rename/delete types and fields) push to CloudKit and
        // peers learn about them. Same mirror pattern as ObjectEngine.
        schema.sync = sync

        // Rebuild the FTS5 index on every launch — cheap for our row
        // counts and immune to a missed write or a restored backup.
        SearchService.reindexAll(schema: schema)

        // Phase 4: kick off CloudKit sync. Runs async; the rest of the
        // app launches normally regardless of sync state. If iCloud
        // / entitlement / container isn't available, sync transitions to
        // `.disabled` and the app stays fully usable locally.
        // Skipped under XCTest — CloudKit's account check stalls the
        // test runner connection (we hit the XCTest timeout because the
        // host app's startup tasks block on iCloud auth).
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            sync.start(schema: schema)
        }

        // Default detail pane is Today; type selection is left nil so the
        // sidebar's Today row reads as selected.
        selectedTypeId = nil
        showTodayInDetail = true

        reloadAll()

        // ⌘1…⌘9 menu commands post a notification with a 1-based
        // index; resolve here against `schema.visibleTypes` and route
        // to the existing `selectedTypeId` binding so the sidebar
        // reflects the change naturally.
        NotificationCenter.default.addObserver(
            forName: AppState.jumpToTypeIndexNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let index = note.userInfo?["index"] as? Int else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let visible = self.schema.visibleTypes
                guard index >= 1, index <= visible.count else { return }
                self.selectedTypeId = visible[index - 1].id
                self.showTodayInDetail = false
            }
        }

        // Remote pulls land into DatabaseService directly via
        // CloudKitSyncService.applyRemote, bypassing ObjectEngine's
        // hooks. Without this observer, the sidebar count and the
        // Today panels (driven off appState.objectCount + the schema)
        // wouldn't refresh until the next type switch / restart.
        NotificationCenter.default.addObserver(
            forName: AppState.objectsChangedRemotelyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadAll()
            }
        }
    }

    /// Recovery path invoked from `RecoveryScreen` when the user accepts
    /// "Reset and start fresh". Quarantines the unopenable DB +
    /// settings + attachments into a timestamped sibling folder, then
    /// creates a fresh keyed DB at the original path. On success,
    /// flips `dbHealth` back to `.ok` and reloads the UI.
    func resetUnrecoverableData() {
        do {
            try database.resetUnrecoverableDataAndReopen()
            // Settings file is gone too — reload with the live keystore so
            // the fresh defaults persist on next save.
            settingsStore.load()
            dbHealth = .ok
            reloadAll()
        } catch {
            NSLog("PurpleLife: recovery reset failed — \(error.localizedDescription)")
            dbHealth = .unrecoverable("Recovery failed: \(error.localizedDescription)")
        }
    }

    /// Refresh derived UI state from the database. Called on launch and
    /// after restore. Phase 1 only has the object count; Phase 2 expands
    /// this to load the schema registry, sidebar lists, etc.
    func reloadAll() {
        do {
            objectCount = try database.objectCount()
        } catch {
            NSLog("PurpleLife: objectCount failed — \(error.localizedDescription)")
            objectCount = 0
        }
    }
}
