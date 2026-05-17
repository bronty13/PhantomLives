import XCTest
@testable import PurpleLife

/// Phase B tests for the recovery-key code path. Covers the BIP39
/// encoder/decoder, the keystore-level wrap/unwrap of the DEK under a
/// recovery phrase, the migration path that backfills the envelope
/// for installs pre-dating Phase B, and the end-to-end scenario that
/// simulates "Keychain is gone but the user has their recovery key".
final class RecoveryKeyTests: XCTestCase {

    private func tempSupportDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecoveryKeyTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - BIP39 encoder / decoder

    func test_generateProducesTwentyFourValidWords() {
        let words = RecoveryKey.generate()
        XCTAssertEqual(words.count, 24)
        for w in words {
            XCTAssertNotNil(BIP39Wordlist.indexByWord[w],
                            "Every generated word must be in the BIP39 wordlist; offender: \(w)")
        }
    }

    func test_generatedPhraseRoundTrips() throws {
        let words = RecoveryKey.generate()
        let entropy = try RecoveryKey.entropy(from: words)
        XCTAssertEqual(entropy.count, 32, "256-bit entropy → 32 bytes")

        let reencoded = try RecoveryKey.encode(entropy: entropy)
        XCTAssertEqual(reencoded, words, "Round-trip must produce the same 24 words")
    }

    func test_encodeKnownEntropyMatchesBIP39ReferenceVector() throws {
        // BIP39 test vector from https://github.com/trezor/python-mnemonic/blob/master/vectors.json
        // entropy = 32 bytes of 0xFF → expected 24-word phrase.
        let entropy = Data(repeating: 0xFF, count: 32)
        let words = try RecoveryKey.encode(entropy: entropy)
        let expected = "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo vote"
        XCTAssertEqual(words.joined(separator: " "), expected,
                       "Encode for the all-0xFF reference vector must match BIP39's canonical output")
    }

    func test_decodeStringFormToleratesWhitespaceAndCase() throws {
        let words = RecoveryKey.generate()
        let entropy = try RecoveryKey.entropy(from: words)

        let upperJoined = words.map { $0.uppercased() }.joined(separator: " ")
        XCTAssertEqual(try RecoveryKey.entropy(from: upperJoined), entropy,
                       "Decoder must lowercase the input")

        let weirdSpaced = "  " + words.joined(separator: "   ") + "  \n  "
        XCTAssertEqual(try RecoveryKey.entropy(from: weirdSpaced), entropy,
                       "Decoder must tolerate leading/trailing whitespace and runs of spaces")
    }

    func test_decodeRejectsWrongWordCount() {
        XCTAssertThrowsError(try RecoveryKey.entropy(from: "abandon")) { error in
            guard case RecoveryKey.RecoveryKeyError.wrongWordCount(actual: 1) = error else {
                return XCTFail("Expected wrongWordCount(1), got \(error)")
            }
        }
    }

    func test_decodeRejectsUnknownWord() throws {
        var words = RecoveryKey.generate()
        words[3] = "definitelynotabip39word"
        XCTAssertThrowsError(try RecoveryKey.entropy(from: words)) { error in
            guard case RecoveryKey.RecoveryKeyError.wordNotInList(let word) = error else {
                return XCTFail("Expected wordNotInList, got \(error)")
            }
            XCTAssertEqual(word, "definitelynotabip39word")
        }
    }

    func test_decodeRejectsChecksumMismatchForSingleWordTypo() throws {
        let words = RecoveryKey.generate()
        let original = words[22]
        // Find ANY replacement that trips the checksum. Picking a single
        // arbitrary replacement and asserting it throws is flaky:
        // BIP39's checksum is 8 bits, so a random one-word swap leaves
        // the 24th word coincidentally-valid roughly 1/256 of the time.
        // Asserting "exists a wrong word that trips the checksum" is
        // the invariant we actually care about ("the checksum catches
        // single-word typos in expectation"); the loop bounds it
        // deterministically — the entire 2048-word search space is
        // examined, and the test only fails if NO substitution trips
        // it (essentially impossible: requires 2047 SHA-256 outputs to
        // all coincidentally match).
        var trippedReplacement: String?
        var trippedError: Error?
        for candidate in BIP39Wordlist.words where candidate != original {
            var attempt = words
            attempt[22] = candidate
            do {
                _ = try RecoveryKey.entropy(from: attempt)
            } catch {
                trippedReplacement = candidate
                trippedError = error
                break
            }
        }
        XCTAssertNotNil(trippedReplacement,
                        "Some replacement in the 2048-word list must trip the checksum — this is the free typo detection BIP39 gives us")
        XCTAssertEqual(trippedError as? RecoveryKey.RecoveryKeyError, .checksumMismatch)
    }

    func test_isValidPredicateMatchesEntropyDecoding() {
        let goodPhrase = RecoveryKey.format(RecoveryKey.generate())
        XCTAssertTrue(RecoveryKey.isValid(goodPhrase))

        XCTAssertFalse(RecoveryKey.isValid("just a few words here"))
        XCTAssertFalse(RecoveryKey.isValid(""))
        XCTAssertFalse(RecoveryKey.isValid("   "))
    }

    func test_formatHelpersProduceExpectedShape() {
        let words = ["alpha", "beta", "gamma"]
        XCTAssertEqual(RecoveryKey.format(words), "alpha beta gamma")
        XCTAssertEqual(RecoveryKey.formatNumbered(words),
                       "1. alpha\n2. beta\n3. gamma")
    }

    // MARK: - KeyStore integration

    @MainActor
    func test_setupKeychainManagedReturnsRecoveryPhraseAndWritesEnvelope() throws {
        let dir = tempSupportDir()
        let store = KeyStore(supportDirectoryURL: dir)
        store.resetAndWipe()
        defer { store.resetAndWipe() }

        let words = try store.setupKeychainManaged()
        XCTAssertEqual(words.count, 24, "setupKeychainManaged must return the new recovery phrase")
        XCTAssertTrue(store.hasRecoveryEnvelope, "recovery_envelope.json must exist after setup")
        XCTAssertEqual(store.state, .unlocked)
    }

    @MainActor
    func test_unlockWithRecoveryKeyRoundTripsTheSameDEK() throws {
        let dir = tempSupportDir()
        let store = KeyStore(supportDirectoryURL: dir)
        store.resetAndWipe()
        defer {
            // Cleanup uses a fresh store keyed off the same dir — the
            // original `store` instance is gone by this point.
            KeyStore(supportDirectoryURL: dir).resetAndWipe()
        }

        let words = try store.setupKeychainManaged()
        let originalRaw = store.currentKey?.rawData
        XCTAssertNotNil(originalRaw)

        // Simulate the real "Keychain entry is gone but recovery
        // envelope is on disk" scenario by wiping the keychain slot
        // and constructing a *fresh* KeyStore. `lock()` won't clear
        // the in-memory DEK on a Keychain-managed install
        // (`hasPassphrase` is false), so a new store instance is the
        // correct way to mirror what AppState does at launch — its
        // refreshState reads no keychain entry → state = .locked.
        KeychainStore.deleteAll()
        let freshStore = KeyStore(supportDirectoryURL: dir)
        XCTAssertEqual(freshStore.state, .locked,
                       "With Keychain wiped + recovery envelope on disk, the keystore should report .locked")
        XCTAssertNil(freshStore.currentKey)

        // Unlock via the recovery phrase.
        try freshStore.unlockWithRecoveryKey(phrase: RecoveryKey.format(words))
        XCTAssertEqual(freshStore.state, .unlocked)

        let recoveredRaw = freshStore.currentKey?.rawData
        XCTAssertEqual(recoveredRaw, originalRaw,
                       "The DEK recovered via the recovery key must be byte-for-byte identical to the original")
    }

    @MainActor
    func test_unlockWithWrongRecoveryKeyThrowsPassphraseMismatch() throws {
        let dir = tempSupportDir()
        let store = KeyStore(supportDirectoryURL: dir)
        store.resetAndWipe()
        defer { KeyStore(supportDirectoryURL: dir).resetAndWipe() }

        _ = try store.setupKeychainManaged()
        KeychainStore.deleteAll()
        let freshStore = KeyStore(supportDirectoryURL: dir)

        // Generate a different (valid) phrase — wrong DEK, valid format.
        let wrong = RecoveryKey.format(RecoveryKey.generate())
        XCTAssertThrowsError(try freshStore.unlockWithRecoveryKey(phrase: wrong)) { error in
            XCTAssertEqual(error as? KeyStore.KeyStoreError, .passphraseMismatch,
                           "Wrong phrase should reuse the existing .passphraseMismatch error vocabulary")
        }
    }

    @MainActor
    func test_unlockWithoutRecoveryEnvelopeThrowsNotSetup() throws {
        let dir = tempSupportDir()
        let store = KeyStore(supportDirectoryURL: dir)
        store.resetAndWipe()
        defer { store.resetAndWipe() }

        XCTAssertFalse(store.hasRecoveryEnvelope)
        let phrase = RecoveryKey.format(RecoveryKey.generate())
        XCTAssertThrowsError(try store.unlockWithRecoveryKey(phrase: phrase)) { error in
            XCTAssertEqual(error as? KeyStore.KeyStoreError, .notSetup)
        }
    }

    @MainActor
    func test_ensureRecoveryEnvelopeIsNoOpWhenAlreadyPresent() throws {
        let dir = tempSupportDir()
        let store = KeyStore(supportDirectoryURL: dir)
        store.resetAndWipe()
        defer { store.resetAndWipe() }

        _ = try store.setupKeychainManaged()
        XCTAssertTrue(store.hasRecoveryEnvelope)
        let migrated = try store.ensureRecoveryEnvelope()
        XCTAssertNil(migrated, "Envelope already exists — migration must do nothing and return nil")
    }

    /// Hardest scenario: simulate an install from before Phase B
    /// where the user has a working DEK in Keychain but no envelope
    /// on disk. `ensureRecoveryEnvelope` must mint one using the
    /// live DEK so the user gets a recovery key without having to
    /// re-onboard.
    @MainActor
    func test_ensureRecoveryEnvelopeBackfillsForPrePhaseBInstall() throws {
        let dir = tempSupportDir()
        let store = KeyStore(supportDirectoryURL: dir)
        store.resetAndWipe()
        defer { store.resetAndWipe() }

        _ = try store.setupKeychainManaged()
        // Simulate the pre-Phase-B state: delete the envelope but
        // keep the DEK in memory + Keychain.
        try FileManager.default.removeItem(at: dir.appendingPathComponent("recovery_envelope.json"))
        XCTAssertFalse(store.hasRecoveryEnvelope)
        XCTAssertEqual(store.state, .unlocked)
        let originalRaw = store.currentKey?.rawData

        let words = try XCTUnwrap(try store.ensureRecoveryEnvelope())
        XCTAssertEqual(words.count, 24)
        XCTAssertTrue(store.hasRecoveryEnvelope, "Backfill must persist the envelope")

        // The migrated envelope must unlock to the same DEK. Build a
        // fresh store after wiping the keychain so we exercise the
        // real "Keychain lost, recovery envelope on disk" path
        // instead of letting the existing in-memory DEK paper over
        // a possible mismatch.
        KeychainStore.deleteAll()
        let freshStore = KeyStore(supportDirectoryURL: dir)
        try freshStore.unlockWithRecoveryKey(phrase: RecoveryKey.format(words))
        XCTAssertEqual(freshStore.currentKey?.rawData, originalRaw,
                       "Migration envelope must wrap the SAME DEK, not a fresh one — otherwise on-disk data becomes unreadable")
    }

    // MARK: - Reset semantics

    @MainActor
    func test_resetAndWipeRemovesRecoveryEnvelope() throws {
        let dir = tempSupportDir()
        let store = KeyStore(supportDirectoryURL: dir)
        store.resetAndWipe()

        _ = try store.setupKeychainManaged()
        XCTAssertTrue(store.hasRecoveryEnvelope)

        store.resetAndWipe()
        XCTAssertFalse(store.hasRecoveryEnvelope,
                       "resetAndWipe must remove the recovery envelope alongside the keystore and marker")
    }

    // MARK: - Phase B.5 — Backup integration

    /// The auto-backup ZIP must include `recovery_envelope.json`.
    /// Without this, a user restoring a backup on a new Mac (or
    /// after a Reset) would have the DB but no envelope to unlock
    /// it with — defeating the whole recovery story.
    @MainActor
    func test_backupZipIncludesRecoveryEnvelope() throws {
        let supportDir = tempSupportDir()
        let backupDir = tempSupportDir()
        let store = KeyStore(supportDirectoryURL: supportDir)
        store.resetAndWipe()
        defer { KeyStore(supportDirectoryURL: supportDir).resetAndWipe() }

        _ = try store.setupKeychainManaged()
        XCTAssertTrue(store.hasRecoveryEnvelope, "Setup must have written the envelope")

        let archiveURL = try BackupService.runBackup(supportDir: supportDir, backupDir: backupDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))

        // Unzip into a staging dir and confirm the envelope made it
        // into the archive.
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("recoverykey-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-q", archiveURL.path, "-d", staging.path]
        try proc.run()
        proc.waitUntilExit()
        XCTAssertEqual(proc.terminationStatus, 0)

        let restoredEnvelope = staging.appendingPathComponent("recovery_envelope.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: restoredEnvelope.path),
                      "recovery_envelope.json must be present in every auto-backup ZIP — without it, the user can't recover on a new Mac")
    }

    /// End-to-end Mac A → backup → Mac B scenario. Verifies the
    /// full promise of Phase B: a user can take a backup on one
    /// Mac, carry their recovery key + the ZIP to a clean Mac, and
    /// unlock the data with no Keychain involvement at all on the
    /// destination side.
    @MainActor
    func test_endToEndRestoreOnNewMacWithRecoveryKey() throws {
        // === Mac A ===
        let macA = tempSupportDir()
        let backupDir = tempSupportDir()
        let storeA = KeyStore(supportDirectoryURL: macA)
        storeA.resetAndWipe()
        defer { KeyStore(supportDirectoryURL: macA).resetAndWipe() }

        let words = try storeA.setupKeychainManaged()
        let originalDEK = storeA.currentKey?.rawData
        XCTAssertNotNil(originalDEK)

        let archiveURL = try BackupService.runBackup(supportDir: macA, backupDir: backupDir)

        // === Mac B ===
        let macB = tempSupportDir()
        // Unzip Mac A's backup into Mac B's empty support dir.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-q", archiveURL.path, "-d", macB.path]
        try proc.run()
        proc.waitUntilExit()
        XCTAssertEqual(proc.terminationStatus, 0)

        // Construct KeyStore against Mac B. Different supportDirectoryURL
        // → different keychainDEKAccount, so Mac A's keychain entry
        // is irrelevant to Mac B's state.
        let storeB = KeyStore(supportDirectoryURL: macB)
        defer { storeB.resetAndWipe() }
        XCTAssertTrue(storeB.hasRecoveryEnvelope,
                      "Backup restore must drop the envelope into place on Mac B")
        XCTAssertEqual(storeB.state, .locked,
                       "With envelope on disk but no Mac-B keychain entry, the store must report .locked")

        // Unlock on Mac B using the phrase from Mac A.
        try storeB.unlockWithRecoveryKey(phrase: RecoveryKey.format(words))
        XCTAssertEqual(storeB.state, .unlocked)
        XCTAssertEqual(storeB.currentKey?.rawData, originalDEK,
                       "RELEASE BLOCKER: cross-Mac recovery via backup + phrase must reproduce the EXACT original DEK, " +
                       "otherwise the SQLCipher DB inside the backup ZIP stays unreadable on Mac B.")
    }
}
