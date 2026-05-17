import Foundation
import SwiftUI
import Combine
import AppKit

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

    /// Phase B (2026-05-15) — non-nil when a 24-word recovery key has
    /// just been generated and the user hasn't yet confirmed they've
    /// saved it. The first-launch save-recovery-key sheet (Phase B.3)
    /// observes this and forces the user through a confirmation
    /// typeback before clearing it. While non-nil, ContentView gates
    /// the main app UI so the user can't bypass the save flow by
    /// closing a regular sheet.
    ///
    /// **Never persisted, never logged.** The phrase exists in memory
    /// for exactly long enough for the user to copy / print / write
    /// it down. After `confirmRecoveryKeySaved()` clears the property,
    /// the only place the phrase exists is wherever the user put it.
    /// Losing it after that point is a deliberate consequence of the
    /// recovery design — the same threat model as a Bitcoin seed.
    @Published var pendingRecoveryKey: [String]? = nil

    /// Non-nil when `VaultAuthService.authenticate` returned
    /// `.unavailable` — the rare case where neither biometrics nor a
    /// device passcode are configured on this Mac. Without surfacing
    /// it the View → Show Vault menu item looks like it silently does
    /// nothing on a bare local account. `ContentView` observes and
    /// shows an alert with system-settings guidance. The user
    /// dismisses with OK; we nil it back out.
    @Published var vaultUnavailableMessage: String? = nil

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

    /// Tags Increment 3d — when the user clicks "Open in Search…" in
    /// Quick Switcher, the typed query is stashed here so the
    /// advanced Search window can pick it up on appear. Cleared by
    /// SearchScreen after consumption so a subsequent open with no
    /// hand-off (e.g. ⌘⇧F directly) starts blank.
    @Published var searchHandoffQuery: String?

    /// Vault visibility for the current session. Deliberately NOT
    /// persisted — every app launch starts with the Vault locked. The
    /// user reveals via the View → Show Vault menu item (which triggers
    /// Touch ID / device password via `VaultAuthService`) and locks via
    /// View → Lock Vault. Sidebar, search, Quick Switcher, Today
    /// timeline, and the schema library gallery all gate on this flag.
    @Published var vaultRevealed: Bool = false

    /// Controls whether the View → Show Vault menu item is visible.
    /// Gated on the user holding Shift+Option as the menu opens — a
    /// deliberate discoverability dampener so the existence of the
    /// Vault isn't apparent to someone shoulder-surfing the menu bar.
    /// Polled at 4 Hz from a Timer set up in `init()`; cheap, and a
    /// quarter-second latency between pressing the modifier and the
    /// item showing is well within user tolerance for "hold this and
    /// then click the menu." Lock Vault stays visible whenever the
    /// vault is already revealed — re-locking is the obvious
    /// counter-move and shouldn't be hidden behind a modifier.
    @Published var vaultMenuVisible: Bool = false

    /// Application-wide screen lock. When `true`, `ContentView`
    /// replaces the main split view with `AppLockScreen` and refuses
    /// to render anything else until the user re-authenticates. Set
    /// by `lockApp()`; cleared by `unlockApp()`. Independent of the
    /// keystore's lock state: crypto-locking (passphrase mode) is
    /// stacked on top when a passphrase is set, but the screen lock
    /// itself is the user-visible UI gate that works in both modes.
    @Published var appLocked: Bool = false

    /// Combine subscriptions held for the lifetime of the AppState.
    /// Currently bridges `SettingsStore.objectWillChange` into our own
    /// `objectWillChange` so a settings mutation (theme switch,
    /// appearance change, etc.) re-renders every view observing
    /// AppState. Without this, mutating a nested `@Published` on a
    /// nested ObservableObject doesn't propagate up.
    private var cancellables: Set<AnyCancellable> = []

    /// Polls `NSEvent.modifierFlags` at 4 Hz to drive
    /// `vaultMenuVisible`. Held strongly here so it lives as long as
    /// the AppState does; never invalidated explicitly since AppState
    /// is application-lifetime.
    private var vaultMenuTimer: Timer?

    /// Last user-input timestamp — drives Vault auto-lock. Updated
    /// by the local NSEvent monitor on every key/mouse/scroll event.
    /// Initialized to "now" so a freshly-launched-but-revealed Vault
    /// doesn't auto-lock the moment the timer first ticks.
    private var lastActivityAt: Date = Date()

    /// Token for the activity monitor; held so it can be removed if
    /// we ever want to tear down (we currently don't — AppState lives
    /// for the whole process).
    private var activityMonitor: Any?

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
            // Belt-and-suspenders: if the on-disk database file looks
            // SQLCipher-encrypted (non-zero, no SQLite magic header),
            // we have data that was written by a previous DEK. Even
            // if `KeychainStore.entryStatus` says the slot is absent
            // — e.g. someone ran `security delete-generic-password`
            // directly — bootstrapping a fresh DEK here destroys the
            // ability to ever decrypt that file. Surface the recovery
            // UX instead.
            let dbLooksEncrypted = database.databaseFileLooksEncrypted()
            do {
                // Phase B (2026-05-15) — capture the generated
                // recovery phrase. The user MUST see this before
                // we hand them a functioning app; the value is
                // stashed in `pendingRecoveryKey` and the
                // save-recovery-key sheet (Phase B.3) gates the
                // rest of the UI until the user confirms saving
                // it.
                let phrase = try keyStore.setupKeychainManaged()
                pendingRecoveryKey = phrase
                if dbLooksEncrypted {
                    // We bootstrapped successfully (no entry conflict),
                    // but encrypted data exists on disk that was
                    // written by some PRIOR DEK that's now gone. The
                    // newly-generated DEK can't decrypt it. Recovery
                    // UX takes over.
                    dbHealth = .unrecoverable(
                        "PurpleLife found encrypted data on disk but no Keychain entry to unlock it. " +
                        "The Keychain entry may have been deleted directly (e.g. via " +
                        "`security delete-generic-password -s com.purplelife`) or removed by another app or system tool."
                    )
                }
            } catch KeyStore.KeyStoreError.keychainEntryAlreadyExists {
                // A Keychain entry exists at our account but
                // `getData` returned nil — almost always a transient
                // unlock / auth issue. Refusing to overwrite is the
                // load-bearing safety check that keeps the DEK alive
                // for a future launch to read again. Surface the
                // situation so the user can quit and retry, restore
                // from Time Machine, or reset deliberately.
                NSLog("PurpleLife: Keychain entry present but unreadable — refusing to overwrite.")
                dbHealth = .unrecoverable(
                    "PurpleLife's Keychain entry exists but can't be read right now. " +
                    "This is usually a transient Keychain issue. Quit and try again; " +
                    "if the problem persists, restore from Time Machine, or Reset to start fresh."
                )
            } catch KeyStore.KeyStoreError.everBootedButKeychainGone {
                // Phase A.2 (2026-05-15) — the per-install
                // `boot_state.json` marker says this install has
                // launched successfully before, but the Keychain
                // slot is now genuinely absent. The keystore refused
                // to create a fresh DEK; keep `.notSetup` and let
                // the recovery screen offer Time Machine / (Phase B+)
                // recovery key as live paths. Don't paper over this
                // by bootstrapping silently — that's the trap.
                NSLog("PurpleLife: ever-booted marker present but Keychain entry gone — refusing to bootstrap a fresh DEK.")
                dbHealth = .unrecoverable(
                    "PurpleLife has launched successfully on this Mac before, but the " +
                    "Keychain entry that unlocks your data is no longer available. " +
                    "This usually means it was deleted out-of-band — check Time Machine for a " +
                    "snapshot of ~/Library/Keychains/login.keychain-db from before the problem started. " +
                    "If you have no backup, you can Reset to start fresh; the unreadable data is " +
                    "preserved on disk in case the key can be recovered later."
                )
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
        // Phase A.2 (2026-05-15) — mark the per-install ever-booted
        // marker as soon as we know the keystore is unlocked AND the
        // DB pool is live. Future launches against an empty Keychain
        // slot will then refuse to bootstrap a fresh DEK, preserving
        // Time Machine / recovery-key paths. Skipped under XCTest:
        // tests use per-process temp support dirs that don't persist
        // across runs, so a marker would only confuse the next test
        // process. Production launches that reach this line have
        // verified keystore.state == .unlocked AND database is not
        // on the placeholder pool — the dbHealth == .ok check covers
        // both via the guards above.
        if keyStore.state == .unlocked,
           dbHealth == .ok,
           ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            BootState.markBooted(in: DatabaseService.supportDirectory)

            // Phase B (2026-05-15) — migration for installs that
            // pre-date the recovery-key work. These users have a
            // perfectly good DEK in their Keychain but no
            // recovery_envelope.json yet, which means a future
            // Keychain loss would put them back in the trap we just
            // fixed. Generating the envelope on-the-fly here from
            // the live DEK gives them the same recovery path new
            // installs get. `ensureRecoveryEnvelope` is a no-op
            // when the envelope already exists, so this is safe
            // to call on every launch.
            if pendingRecoveryKey == nil {
                if let migrated = try? keyStore.ensureRecoveryEnvelope() {
                    pendingRecoveryKey = migrated
                }
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
        // Wire AttachmentService → sync so add() / deleteRow() fan
        // out to CloudKit. The PurpleAttachmentRef CKRecord type
        // carries the encrypted asset bytes alongside the row
        // metadata; peers materialize the row + decrypt the asset
        // on pull.
        AttachmentService.sync = sync

        // Rebuild the FTS5 index on every launch — cheap for our row
        // counts and immune to a missed write or a restored backup.
        SearchService.reindexAll(schema: schema)

        // Wire the cross-cutting tag service to the settings store
        // (where the vocabulary lives) and rebuild the derived
        // `record_tags` index from every record's `_tags` field.
        // Same launch-time reindex pattern as `SearchService`.
        TagService.settings = settingsStore
        TagService.reindexAll()

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

        // Vault menu visibility + auto-lock — both polled on a single
        // 4 Hz timer to keep the housekeeping cheap. The same tick
        // (a) updates `vaultMenuVisible` from the live modifier flags
        // and (b) checks whether the Vault should auto-lock for
        // inactivity. Skipped under XCTest; a background Timer would
        // leak across tests and a polling global isn't worth the
        // bother in headless runs anyway.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            // Activity monitor — stamps `lastActivityAt` on any user
            // input that hits our app's run loop. Cheap; the monitor
            // is invoked synchronously per event but our handler is
            // a single property write.
            activityMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .leftMouseDown, .rightMouseDown,
                           .otherMouseDown, .mouseMoved, .scrollWheel]
            ) { [weak self] event in
                self?.lastActivityAt = Date()
                return event
            }

            vaultMenuTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                // Timer fires on the main RunLoop, so the body is
                // already main-actor in practice — `assumeIsolated`
                // tells Swift 6 the same. Same pattern as
                // `ObjectEngine.registerUndo`.
                MainActor.assumeIsolated {
                    guard let self else { return }

                    // Vault-menu modifier polling.
                    let mods = NSEvent.modifierFlags
                    let held = mods.contains(.shift) && mods.contains(.option)
                    if self.vaultMenuVisible != held {
                        self.vaultMenuVisible = held
                    }

                    // Vault auto-lock for inactivity. Only fires when the
                    // vault is currently revealed and the user has
                    // configured a non-zero threshold. The Date comparison
                    // is on wall-clock time (Date()), not monotonic — fine
                    // here; we want "wall-clock seconds since the user
                    // last touched anything," and a sleep/wake cycle that
                    // bumps the clock forward should still lock the vault.
                    let threshold = self.settings.vaultAutoLockAfterSeconds
                    if self.vaultRevealed && threshold > 0 {
                        let idle = Date().timeIntervalSince(self.lastActivityAt)
                        if idle >= Double(threshold) {
                            self.lockVault()
                        }
                    }
                }
            }
        }

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

    /// Phase B (2026-05-15) — user has confirmed they've saved their
    /// recovery key. Clears `pendingRecoveryKey` so the gating sheet
    /// dismisses and the main app UI becomes reachable. The phrase
    /// is dropped from memory at this point; if the user lied about
    /// saving it, that's their problem — and the threat model we
    /// chose, by design.
    func confirmRecoveryKeySaved() {
        pendingRecoveryKey = nil
    }

    /// Phase B.4 (2026-05-15) — recovery screen "Enter recovery key"
    /// path. Tries to unlock the keystore using the user-supplied
    /// 24-word phrase, then reopens the SQLCipher DB with the
    /// recovered DEK. On success: flips `dbHealth = .ok`, reloads
    /// the UI, app is usable again. On failure: returns the typed
    /// error so the UX can surface a specific message (wrong key,
    /// no envelope, etc.). Never mutates `dbHealth` on failure —
    /// the recovery screen stays visible so the user can try again.
    @discardableResult
    func tryRecoveryKeyUnlock(phrase: String) -> Result<Void, Error> {
        do {
            // Validate the phrase up front so single-word typos
            // (caught by the BIP39 checksum) surface as a specific
            // error instead of a generic "wrong key" via the
            // AES-GCM tag mismatch path.
            _ = try RecoveryKey.entropy(from: phrase)
            try keyStore.unlockWithRecoveryKey(phrase: phrase)
            try database.reopenDatabase()
            if database.isUsingPlaceholderPool {
                return .failure(KeyStore.KeyStoreError.corrupt)
            }
            dbHealth = .ok
            // Write the ever-booted marker now that we've fully
            // recovered — the same marker would otherwise stay
            // missing across the recovery, and a future Keychain
            // loss would re-open the data-loss trap.
            BootState.markBooted(in: DatabaseService.supportDirectory)
            reloadAll()
            return .success(())
        } catch {
            return .failure(error)
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

    // MARK: - Vault

    /// Prompt for Touch ID / device password and reveal the Vault on
    /// success. No-op when the Vault is already revealed. Called from
    /// the View → Show Vault menu item. Failures (cancel, lockout)
    /// leave `vaultRevealed = false` without surfacing a banner —
    /// the menu item itself is the user's affordance to try again.
    func revealVault() async {
        guard !vaultRevealed else { return }
        let result = await VaultAuthService.authenticate(reason: "Show the Vault")
        if case .success = result {
            // Reset the inactivity stamp on every reveal so the auto-
            // lock timer starts fresh and a stale `lastActivityAt`
            // from before the unlock doesn't snap the vault closed
            // again on the very next tick.
            lastActivityAt = Date()
            vaultRevealed = true
        } else if case .unavailable(let detail) = result {
            // No biometrics + no passcode on this Mac. The Vault is
            // unprotectable; surface the state so the user understands
            // why Show Vault appeared to do nothing. ContentView
            // observes `vaultUnavailableMessage` and shows an alert.
            NSLog("PurpleLife: Vault unlock unavailable — \(detail)")
            vaultUnavailableMessage = "The Vault needs Touch ID or a Mac login password to unlock, and this Mac has neither configured. Set a login password in System Settings → Touch ID & Password, then try again.\n\n(System detail: \(detail))"
        }
        // .userCancelled / .failed: silent — the user chose to back out
        // (or got the password wrong); they'll re-invoke if they want.
    }

    // MARK: - App-wide lock

    /// Lock the entire application. Both modes the docs mention:
    /// - Always sets `appLocked = true`, which makes `ContentView`
    ///   replace the main UI with `AppLockScreen` until the user
    ///   re-authenticates via Touch ID / device password.
    /// - If a passphrase is configured, ALSO calls `keyStore.lock()`
    ///   to wipe the in-memory DEK so a process-memory snapshot
    ///   can't reveal it. The passphrase prompt comes after the
    ///   screen-lock dismissal in that case.
    /// Side effect: locks the Vault too. A locked app should never
    /// resume with the Vault still revealed.
    func lockApp() {
        if keyStore.hasPassphrase {
            _ = keyStore.lock()
        }
        vaultRevealed = false
        appLocked = true
    }

    /// Clear the screen lock after a successful Touch ID /
    /// device-password challenge from `AppLockScreen`. Doesn't try to
    /// unlock the keystore — passphrase entry is the user's
    /// responsibility from the regular Settings → Security path when
    /// they need the keystore's passphrase-mode session back.
    func unlockApp() {
        lastActivityAt = Date()
        appLocked = false
    }

    /// Hide the Vault for the rest of the session. Called from the
    /// View → Lock Vault menu item and implicitly any time the user
    /// quits the app (since `vaultRevealed` isn't persisted).
    func lockVault() {
        vaultRevealed = false
        // If the user is currently looking at a Vault type when they
        // lock, snap them back to Today so they're not staring at a
        // header for a type that's no longer in their visible list.
        if let selected = selectedTypeId,
           let type = schema.type(id: selected),
           type.isVault {
            selectedTypeId = nil
            showTodayInDetail = true
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
