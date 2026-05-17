import Foundation
import CryptoKit

/// Holds the data-encryption key (DEK) used to seal every PurpleLife
/// persistence file (the SQLite DB key, settings.json, attachment files).
///
/// Two operating modes — both keep data encrypted at rest, the difference
/// is how the DEK is protected:
///
/// **Keychain-managed (default for new installs).** A 256-bit DEK is
/// generated on first launch and stored in the macOS Keychain. The app
/// opens silently on subsequent launches because the Keychain holds the
/// DEK. No `keystore.json` is written to disk. Defends against bare-file
/// exfiltration (the on-disk files are sealed AES-GCM); Keychain ACLs
/// gate access on the running Mac.
///
/// **Passphrase-protected.** Same DEK, additionally wrapped under a KEK
/// derived from the user's passphrase via PBKDF2-HMAC-SHA256 (300k
/// iterations, 16-byte random salt). Wrapped DEK + salt + KDF params
/// live in `keystore.json`. The Keychain still caches the unwrapped DEK
/// after a successful unlock so subsequent launches don't reprompt; the
/// "Lock now" action clears the cache so the next launch demands the
/// passphrase again.
///
/// Changing the passphrase re-wraps the same DEK (millisecond op); no
/// user data is re-encrypted. Removing the passphrase deletes
/// `keystore.json`, leaving the Keychain-only mode in place. Forgetting
/// the passphrase with no Keychain cache means data loss — there is no
/// recovery mechanism. That is the point.
@MainActor
final class KeyStore: ObservableObject {

    enum UnlockState: Equatable {
        case notSetup        // no keystore.json, no Keychain entry
        case locked          // keystore.json exists, DEK not in memory
        case unlocked        // DEK is available; encrypt/decrypt works
    }

    enum KeyStoreError: Error {
        case alreadySetup
        case notSetup
        case locked
        case passphraseMismatch
        case corrupt
        case noPassphraseSet
        /// `setupKeychainManaged` aborted because a Keychain slot for our
        /// DEK already exists — we can't read it (so we'd silently
        /// overwrite it without this guard), but its presence means
        /// there's encrypted data on disk somewhere that belongs to
        /// it. Surface the situation to the user instead of destroying
        /// the key.
        case keychainEntryAlreadyExists

        /// Phase A.2 (2026-05-15) — `setupKeychainManaged` aborted
        /// because the per-install `boot_state.json` marker exists
        /// but the Keychain slot is empty. The marker says "this
        /// install has launched successfully before, data has been
        /// written under some prior DEK"; the absent slot says "that
        /// DEK is gone." Generating a fresh DEK here would foreclose
        /// every recovery path (Time Machine restore of the Keychain
        /// entry, future user-held recovery key). The keystore
        /// refuses; AppState surfaces the recovery screen *without*
        /// any new DEK having been created.
        case everBootedButKeychainGone
    }

    @Published private(set) var state: UnlockState = .notSetup

    /// True when `keystore.json` exists on disk (passphrase-protected mode).
    /// When false, the DEK is held only by the Keychain.
    @Published private(set) var hasPassphrase: Bool = false

    /// Wired by `AppState` at launch — gives the keystore access to
    /// the CloudKit sync surface so Tier 4 backup pushes / fetches
    /// can fire. Optional so tests that don't initialize sync still
    /// work; weak so the keystore doesn't keep the sync service
    /// alive past AppState's tear-down.
    weak var sync: CloudKitSyncService?

    private let fileURL: URL
    /// Current DEK. Non-nil iff state == .unlocked. Never serialised directly.
    private var dek: SymmetricKey?

    /// Per-install Keychain account. Derived from the support dir path so
    /// separate installs (including test temp directories) don't share a
    /// DEK cache slot.
    private let keychainDEKAccount: String
    private static let kdfIterations = 300_000
    private static let saltLength = 16

    // MARK: - On-disk representation

    /// `keystore.json` contents. Bumping `version` lets us migrate wrap
    /// formats later without breaking existing files.
    private struct Envelope: Codable {
        var version: Int = 1
        var salt: Data                // passphrase KDF salt
        var iterations: Int           // KDF iterations (future-proofing)
        var wrappedDEK: Data          // AES-GCM combined-format sealed box
    }

    /// `recovery_envelope.json` contents (Phase B, 2026-05-15). Holds
    /// the DEK wrapped under a KEK derived from the user's 24-word
    /// recovery phrase. Separate file from `keystore.json` so the
    /// passphrase-mode envelope and the recovery-key envelope are
    /// independent — a user can have either, both, or (rarely)
    /// neither. Auto-backup picks the file up automatically because
    /// `BackupService` zips the whole support directory.
    private struct RecoveryEnvelope: Codable {
        var version: Int = 1
        var salt: Data
        var iterations: Int
        var wrappedDEK: Data
    }

    /// Path to `recovery_envelope.json`. Stored alongside the
    /// keystore envelope; lifecycle managed by the helpers below.
    private let recoveryFileURL: URL

    // MARK: - Init

    init(supportDirectoryURL: URL) {
        self.fileURL = supportDirectoryURL.appendingPathComponent("keystore.json")
        self.recoveryFileURL = supportDirectoryURL.appendingPathComponent("recovery_envelope.json")
        // Full SHA-256 hex of the support-directory path. Truncating to
        // 48 bits added no value and made colliding-path attacks plausible
        // (2^24 expected attempts) — there's no length pressure on the
        // Keychain account name.
        let pathHash = SHA256.hash(data: Data(supportDirectoryURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined()
        self.keychainDEKAccount = "dek-v1-\(pathHash)"
        refreshState()
    }

    /// True iff a recovery-envelope file exists on disk. Used by
    /// `AppState` to decide whether the recovery screen should
    /// expose an "Enter recovery key" path. Independent of
    /// `hasPassphrase`: an install can have both, either, or
    /// (legacy, pre-Phase-B) neither.
    var hasRecoveryEnvelope: Bool {
        FileManager.default.fileExists(atPath: recoveryFileURL.path)
    }

    /// Recompute `state` and `hasPassphrase`, then try a silent unlock via
    /// the Keychain cache so the rest of the app can decide whether it
    /// needs to prompt.
    func refreshState() {
        let envelopeExists = FileManager.default.fileExists(atPath: fileURL.path)
        hasPassphrase = envelopeExists

        // Tier 3 — probe local Keychain first; fall back to the per-Mac
        // iCloud Keychain mirror. If the mirror fires (local lost,
        // iCloud trust circle still has it), backfill the local copy
        // so subsequent launches use the fast non-sync path.
        if let cached = KeychainStore.getDataIncludingICloudMirror(for: keychainDEKAccount),
           cached.count >= 16 {
            self.dek = SymmetricKey(data: cached)
            self.state = .unlocked
            // Backfill: if local was missing but mirror provided the
            // bytes, write a local copy so the next launch doesn't
            // round-trip through iCloud Keychain again.
            if KeychainStore.getData(for: keychainDEKAccount, synchronizable: false) == nil {
                try? KeychainStore.setData(cached, for: keychainDEKAccount, synchronizable: false)
                NSLog("PurpleLife: KeyStore recovered DEK from iCloud Keychain mirror — local Keychain backfilled.")
            }
            return
        }

        // No Keychain cache. State depends on whether *any* unlock
        // envelope is on disk: a passphrase envelope (legacy) or
        // a Phase B recovery envelope. Either path can take us
        // from `.locked` to `.unlocked`. Only when neither file
        // is present do we treat this as a genuine fresh install.
        self.dek = nil
        if envelopeExists || hasRecoveryEnvelope {
            self.state = .locked
        } else {
            self.state = .notSetup
        }
    }

    // MARK: - First-launch setup

    /// First-launch path A: generate a DEK and store it in the Keychain only
    /// (no passphrase). Defends against bare-file exfiltration; subsequent
    /// launches open silently. The user can layer a passphrase on top later
    /// via `addPassphrase(_:)`.
    @discardableResult
    func setupKeychainManaged() throws -> [String] {
        guard state == .notSetup else { throw KeyStoreError.alreadySetup }
        // Refuse to overwrite an existing slot. `KeychainStore.getData`
        // returns nil for "item not found" AND for any transient query
        // failure (locked Keychain, auth issue, …) — without this
        // check we silently overwrite the existing DEK with a fresh
        // one and the on-disk encrypted DB becomes unrecoverable.
        // Real incident: 2026-05-12 saw repeat data-loss because
        // refreshState misread a transient miss as "first launch".
        let status = KeychainStore.entryStatus(for: keychainDEKAccount)
        if status != .absent {
            throw KeyStoreError.keychainEntryAlreadyExists
        }
        // Tier 3 — same defense against the iCloud Keychain mirror.
        // refreshState should have picked up the mirror via
        // getDataIncludingICloudMirror and unlocked us; if it didn't
        // but the mirror entry still exists (a transient iCloud
        // failure, locked Keychain, etc.), minting a fresh DEK here
        // would overwrite the mirror and orphan whatever the prior
        // DEK was protecting. The per-Mac mirror account means a
        // genuinely-fresh Mac has no entry under its own machine ID
        // and this check correctly passes for first launches.
        let mirrorAccount = KeychainStore.iCloudMirrorAccount(for: keychainDEKAccount)
        let mirrorStatus = KeychainStore.entryStatus(for: mirrorAccount, synchronizable: true)
        if mirrorStatus != .absent {
            throw KeyStoreError.keychainEntryAlreadyExists
        }
        // Phase A.2 (2026-05-15) — second guard: even when the slot
        // is *definitively* absent, refuse to create a fresh DEK if
        // the ever-booted marker says this install has run
        // successfully before. The slot being absent now plus the
        // marker existing implies the Keychain entry was destroyed
        // out-of-band; generating a fresh DEK at this point would
        // make every byte already on disk unreadable forever, and —
        // critically — would foreclose recovery paths that still
        // exist (Time Machine restoring the Keychain entry, the
        // Phase B user-held recovery key). The keystore stays in
        // `.notSetup`; AppState surfaces the recovery screen.
        // Real incident: 2026-05-15 (#4). See HANDOFF.md.
        if BootState.everBooted(in: supportDirectory) {
            throw KeyStoreError.everBootedButKeychainGone
        }
        let newDEK = SymmetricKey(size: .bits256)
        self.dek = newDEK
        self.state = .unlocked
        self.hasPassphrase = false
        cacheDEKInKeychain()
        // Phase B (2026-05-15) — every fresh keystore also gets a
        // 24-word recovery key. The wrapped DEK lands in
        // `recovery_envelope.json` (auto-included in every backup
        // ZIP by `BackupService`). The phrase is returned to the
        // caller, which must show it to the user before allowing
        // the app to continue; we deliberately do NOT log or store
        // the phrase anywhere else — the user is the only persistence
        // path, by design.
        return try writeRecoveryEnvelope(for: newDEK)
    }

    /// Support directory derived from `fileURL` (which is
    /// `<supportDir>/keystore.json`). The keystore was constructed
    /// with a `supportDirectoryURL` parameter; recovering it from the
    /// stored `fileURL` avoids duplicating the field. Used by the
    /// Phase A.2 ever-booted marker check above.
    private var supportDirectory: URL {
        fileURL.deletingLastPathComponent()
    }

    /// First-launch path B: generate a DEK and wrap it under a passphrase.
    /// Stricter than Keychain-managed mode — `lock()` forces a re-prompt on
    /// next access. The Keychain still caches the unwrapped DEK for the
    /// current session so subsequent reads stay snappy.
    ///
    /// Phase B addition: passphrase users also get a 24-word recovery
    /// key. The recovery envelope is independent of the passphrase
    /// envelope — losing the passphrase no longer means losing the
    /// data. The returned phrase MUST be surfaced to the user before
    /// the app proceeds.
    @discardableResult
    func setupWithPassphrase(_ passphrase: String) throws -> [String] {
        guard state == .notSetup else { throw KeyStoreError.alreadySetup }
        let newDEK = SymmetricKey(size: .bits256)
        let salt = Crypto.randomBytes(Self.saltLength)
        let kek = try Crypto.deriveKey(passphrase: passphrase,
                                       salt: salt,
                                       iterations: Self.kdfIterations)
        let wrapped = try Crypto.encrypt(newDEK.rawData, using: kek)
        let env = Envelope(salt: salt,
                           iterations: Self.kdfIterations,
                           wrappedDEK: wrapped)
        try persist(env)
        self.dek = newDEK
        self.state = .unlocked
        self.hasPassphrase = true
        cacheDEKInKeychain()
        return try writeRecoveryEnvelope(for: newDEK)
    }

    /// Migration path: if the keystore is `.unlocked` (the silent-
    /// fast-path) but no recovery envelope exists on disk, generate
    /// one now using the live DEK. Returns the new phrase; the caller
    /// must surface it to the user. Used on the first launch of a
    /// Phase B build for installs that pre-date this work — without
    /// it, existing users would never get a recovery key. Safe to
    /// call on every launch: when an envelope already exists, returns
    /// nil and does no work.
    func ensureRecoveryEnvelope() throws -> [String]? {
        guard state == .unlocked, let dek else { return nil }
        if hasRecoveryEnvelope { return nil }
        return try writeRecoveryEnvelope(for: dek)
    }

    /// Phase B unlock: derive the KEK from a recovery phrase, unwrap
    /// the DEK from `recovery_envelope.json`, cache in Keychain so
    /// subsequent launches are silent again. Reuses
    /// `KeyStoreError.passphraseMismatch` for "wrong recovery key" —
    /// the AES-GCM tag check is the same regardless of which secret
    /// the KEK was derived from, and AppState's existing error
    /// surfacing already speaks that vocabulary. The
    /// `RecoveryKey.entropy(from:)` checksum check upstream catches
    /// single-word typos before we even get here.
    func unlockWithRecoveryKey(phrase: String) throws {
        guard hasRecoveryEnvelope else { throw KeyStoreError.notSetup }
        let env = try loadRecoveryEnvelope()
        let kek = try RecoveryKey.deriveKEK(
            phrase: phrase,
            salt: env.salt,
            iterations: env.iterations
        )
        let rawDEK: Data
        do {
            rawDEK = try Crypto.decrypt(env.wrappedDEK, using: kek)
        } catch {
            throw KeyStoreError.passphraseMismatch
        }
        self.dek = SymmetricKey(data: rawDEK)
        self.state = .unlocked
        cacheDEKInKeychain()
    }

    // MARK: - Recovery envelope helpers

    /// Generate a fresh 24-word phrase, derive a KEK, wrap the
    /// supplied DEK, and persist the envelope atomically. Returns
    /// the words for the UX to show. **Never** logs or stores the
    /// phrase outside the returned value — losing it after the
    /// caller forgets it is a deliberate, documented property of
    /// the recovery design.
    private func writeRecoveryEnvelope(for dek: SymmetricKey) throws -> [String] {
        let words = RecoveryKey.generate()
        let phrase = RecoveryKey.format(words)
        let salt = Crypto.randomBytes(Self.saltLength)
        let kek = try RecoveryKey.deriveKEK(
            phrase: phrase,
            salt: salt,
            iterations: Self.kdfIterations
        )
        let wrapped = try Crypto.encrypt(dek.rawData, using: kek)
        let env = RecoveryEnvelope(
            salt: salt,
            iterations: Self.kdfIterations,
            wrappedDEK: wrapped
        )
        let data = try JSONEncoder().encode(env)
        try data.write(to: recoveryFileURL, options: .atomic)
        return words
    }

    private func loadRecoveryEnvelope() throws -> RecoveryEnvelope {
        let data = try Data(contentsOf: recoveryFileURL)
        return try JSONDecoder().decode(RecoveryEnvelope.self, from: data)
    }

    // MARK: - Unlock / lock

    /// Derive KEK from `passphrase`, unwrap DEK, store in memory. Throws
    /// `.passphraseMismatch` on wrong passphrase (AES-GCM tag check fails).
    func unlock(passphrase: String) throws {
        let env = try loadEnvelope()
        let kek = try Crypto.deriveKey(passphrase: passphrase,
                                       salt: env.salt,
                                       iterations: env.iterations)
        let rawDEK: Data
        do {
            rawDEK = try Crypto.decrypt(env.wrappedDEK, using: kek)
        } catch {
            throw KeyStoreError.passphraseMismatch
        }
        self.dek = SymmetricKey(data: rawDEK)
        self.state = .unlocked
        self.hasPassphrase = true
        cacheDEKInKeychain()
    }

    /// Drop the in-memory DEK and remove the Keychain cache. Only meaningful
    /// when a passphrase is set — without one, there's nothing to re-prompt
    /// for, so `lock()` would brick the install. Returns `false` and is a
    /// no-op in Keychain-managed mode.
    @discardableResult
    func lock() -> Bool {
        guard hasPassphrase else { return false }
        dek = nil
        state = .locked
        try? KeychainStore.delete(account: keychainDEKAccount)
        return true
    }

    // MARK: - Passphrase management

    /// Layer a passphrase on top of an existing Keychain-managed install.
    /// Wraps the current DEK; the Keychain cache stays in place so this
    /// session doesn't suddenly re-prompt. `lock()` becomes meaningful
    /// after this call.
    func addPassphrase(_ passphrase: String) throws {
        guard let dek else { throw KeyStoreError.locked }
        guard !hasPassphrase else { throw KeyStoreError.alreadySetup }
        let salt = Crypto.randomBytes(Self.saltLength)
        let kek = try Crypto.deriveKey(passphrase: passphrase,
                                       salt: salt,
                                       iterations: Self.kdfIterations)
        let wrapped = try Crypto.encrypt(dek.rawData, using: kek)
        let env = Envelope(salt: salt,
                           iterations: Self.kdfIterations,
                           wrappedDEK: wrapped)
        try persist(env)
        self.hasPassphrase = true
    }

    /// Swap the wrapping passphrase without touching the DEK, so no user
    /// data needs re-encryption. Requires the keystore to be unlocked AND
    /// to have a passphrase already set.
    func changePassphrase(oldPassphrase: String, newPassphrase: String) throws {
        guard hasPassphrase else { throw KeyStoreError.noPassphraseSet }
        // Verify old via a fresh unlock pass (doesn't mutate state beyond
        // confirming the current DEK matches).
        let env = try loadEnvelope()
        let oldKEK = try Crypto.deriveKey(passphrase: oldPassphrase,
                                          salt: env.salt,
                                          iterations: env.iterations)
        let verified: Data
        do {
            verified = try Crypto.decrypt(env.wrappedDEK, using: oldKEK)
        } catch {
            throw KeyStoreError.passphraseMismatch
        }
        // Re-wrap the same DEK with the new passphrase + fresh salt.
        let dekKey = SymmetricKey(data: verified)
        let newSalt = Crypto.randomBytes(Self.saltLength)
        let newKEK = try Crypto.deriveKey(passphrase: newPassphrase,
                                          salt: newSalt,
                                          iterations: Self.kdfIterations)
        let newWrapped = try Crypto.encrypt(dekKey.rawData, using: newKEK)
        let newEnv = Envelope(salt: newSalt,
                              iterations: Self.kdfIterations,
                              wrappedDEK: newWrapped)
        try persist(newEnv)
        self.dek = dekKey
        self.state = .unlocked
        self.hasPassphrase = true
        cacheDEKInKeychain()
    }

    /// Remove the passphrase wrapping, falling back to Keychain-managed mode.
    /// Verifies the current passphrase first so a thief at an unlocked Mac
    /// can't strip protection without proving they know it. Requires the
    /// keystore to be currently unlocked.
    func removePassphrase(currentPassphrase: String) throws {
        guard hasPassphrase else { throw KeyStoreError.noPassphraseSet }
        guard let dek else { throw KeyStoreError.locked }
        let env = try loadEnvelope()
        let kek = try Crypto.deriveKey(passphrase: currentPassphrase,
                                       salt: env.salt,
                                       iterations: env.iterations)
        let verified: Data
        do {
            verified = try Crypto.decrypt(env.wrappedDEK, using: kek)
        } catch {
            throw KeyStoreError.passphraseMismatch
        }
        // Sanity: the unwrapped DEK had better match what's in memory.
        guard verified == dek.rawData else { throw KeyStoreError.corrupt }
        try FileManager.default.removeItem(at: fileURL)
        self.hasPassphrase = false
        // DEK stays in memory and in the Keychain — that's the whole point
        // of "remove passphrase": the install continues to open silently.
    }

    /// Obliterate the keystore and all Keychain items so the user can start
    /// from scratch (e.g. if they forgot their passphrase and accept data loss).
    /// Any encrypted files on disk become unreadable garbage after this —
    /// callers should delete those separately.
    ///
    /// Also clears the Phase A.2 ever-booted marker. Without this,
    /// the next launch would see "marker present + Keychain absent"
    /// and refuse to bootstrap — bouncing the user back into the
    /// recovery screen they just escaped from. Production's Reset
    /// flow goes through `DatabaseService.resetUnrecoverableDataAndReopen`
    /// which already quarantines the marker; clearing it here keeps
    /// `resetAndWipe()` semantically self-contained for any other
    /// caller.
    func resetAndWipe() {
        dek = nil
        state = .notSetup
        hasPassphrase = false
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: recoveryFileURL)
        try? FileManager.default.removeItem(at: BootState.markerURL(in: supportDirectory))
        KeychainStore.deleteAll()
    }

    /// Test-only escape hatch to override `state` and `dek` so a test
    /// can exercise the "looks like first launch even though the
    /// Keychain entry still exists" scenario that `setupKeychainManaged`
    /// guards against. Used by the regression test for the silent-
    /// data-loss bug; not exposed to production callers because the
    /// state machine wants to own its transitions.
    func test_forceState(_ newState: UnlockState) {
        state = newState
        if newState != .unlocked { dek = nil }
    }

    // MARK: - Encrypt / decrypt passthroughs

    /// Encrypt arbitrary data with the current DEK. Throws `.locked` when
    /// the keystore isn't open.
    func encrypt(_ plaintext: Data) throws -> Data {
        guard let dek else { throw KeyStoreError.locked }
        return try Crypto.encrypt(plaintext, using: dek)
    }

    /// Decrypt data produced by `encrypt`. Throws on wrong key or tamper.
    func decrypt(_ ciphertext: Data) throws -> Data {
        guard let dek else { throw KeyStoreError.locked }
        return try Crypto.decrypt(ciphertext, using: dek)
    }

    var isUnlocked: Bool { state == .unlocked }

    /// The current DEK. `SymmetricKey` is `Sendable`, so this is safe to
    /// ferry across isolation boundaries (SQLCipher and AttachmentService
    /// both need it).
    var currentKey: SymmetricKey? { dek }

    // MARK: - Disk / keychain

    private func persist(_ env: Envelope) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(env)
        try data.write(to: fileURL, options: .atomic)
        // Owner-only perms — the wrapped DEK is useless without the
        // passphrase, but tightening the file mode is cheap defence.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private func loadEnvelope() throws -> Envelope {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw KeyStoreError.notSetup
        }
        let data = try Data(contentsOf: fileURL)
        let dec = JSONDecoder()
        guard let env = try? dec.decode(Envelope.self, from: data) else {
            throw KeyStoreError.corrupt
        }
        return env
    }

    private func cacheDEKInKeychain() {
        guard let dek else { return }
        // Tier 3 — write the DEK to both the local Keychain entry
        // (fast non-sync silent-unlock path) AND the per-Mac iCloud
        // Keychain mirror (synced via the user's iCloud trust circle).
        // The mirror enables silent recovery when the local entry is
        // lost. Best-effort on the iCloud side; if it fails we still
        // have a valid local copy and the keystore is fully usable.
        try? KeychainStore.setDataWithICloudMirror(dek.rawData, for: keychainDEKAccount)
        // Tier 4 — also push a backup copy to CloudKit's private DB,
        // wrapped via Apple's CKKS trust-circle keys (encryptedValues).
        // Fires-and-forgets; pushDEKBackup logs but doesn't propagate
        // failures. The local DEK still functions if the push fails;
        // the backup is purely a recovery convenience that survives
        // iCloud Keychain wipes Tier 3 can't.
        if let sync {
            let payload = dek.rawData
            Task { @MainActor in await sync.pushDEKBackup(dekData: payload) }
        }
    }

    // MARK: - Tier 4: CloudKit DEK backup restore

    /// Async recovery path used by `AppState` when both local Keychain
    /// (Tier 1) and the iCloud Keychain mirror (Tier 3) are gone.
    /// Tries to fetch the per-Mac `PurpleDEKBackup` record from
    /// CloudKit; if found, restores the DEK into local + iCloud
    /// Keychain entries so subsequent launches use the fast path.
    ///
    /// Returns `true` if the DEK was restored and the keystore is now
    /// `.unlocked`. Returns `false` if no backup exists, the fetch
    /// failed, the bytes are wrong-sized, or the sync service isn't
    /// wired. Caller falls back to the recovery screen on `false`.
    func tryRestoreFromCloudKitBackup() async -> Bool {
        guard let sync else { return false }
        guard let dekData = await sync.fetchDEKBackup() else { return false }
        guard dekData.count >= 16 else {
            NSLog("PurpleLife: tryRestoreFromCloudKitBackup — fetched DEK is too short (\(dekData.count) bytes)")
            return false
        }
        let restored = SymmetricKey(data: dekData)
        self.dek = restored
        self.state = .unlocked
        self.hasPassphrase = FileManager.default.fileExists(atPath: fileURL.path)
        // Backfill the local Keychain entry + iCloud mirror so the
        // next launch unlocks silently via Tier 1 / Tier 3 without
        // needing to round-trip through CloudKit again.
        cacheDEKInKeychain()
        NSLog("PurpleLife: KeyStore recovered DEK from CloudKit backup (Tier 4) — local Keychain backfilled.")
        return true
    }
}
