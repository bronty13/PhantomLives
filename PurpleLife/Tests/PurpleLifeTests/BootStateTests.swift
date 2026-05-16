import XCTest
@testable import PurpleLife

/// Phase A.2 ever-booted marker tests. The marker is the load-bearing
/// signal that prevents data-loss incident #4 from recurring:
/// `KeyStore.setupKeychainManaged` consults it before generating a
/// fresh DEK, so an out-of-band Keychain wipe on a known-good install
/// is routed to recovery instead of silently destroying the data.
///
/// Each test uses a per-test temp support dir so the marker file is
/// guaranteed-fresh and doesn't bleed across tests in the bundle.
final class BootStateTests: XCTestCase {

    private func tempSupportDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BootStateTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Marker file behavior

    func test_everBootedIsFalseOnFreshDir() {
        let dir = tempSupportDir()
        XCTAssertFalse(BootState.everBooted(in: dir),
                       "Fresh support dir has no marker — everBooted must be false")
    }

    func test_markBootedWritesMarker() {
        let dir = tempSupportDir()
        BootState.markBooted(in: dir)
        XCTAssertTrue(BootState.everBooted(in: dir))
        let state = BootState.read(in: dir)
        XCTAssertNotNil(state)
        XCTAssertFalse(state?.firstLaunchAt.isEmpty ?? true)
        XCTAssertFalse(state?.lastLaunchAt.isEmpty ?? true)
        XCTAssertEqual(state?.version, 1)
    }

    func test_markBootedPreservesFirstLaunchAtAcrossCalls() {
        let dir = tempSupportDir()
        BootState.markBooted(in: dir)
        let firstRead = BootState.read(in: dir)
        let firstLaunchAt = firstRead?.firstLaunchAt

        Thread.sleep(forTimeInterval: 0.01)
        BootState.markBooted(in: dir)
        let secondRead = BootState.read(in: dir)

        XCTAssertEqual(secondRead?.firstLaunchAt, firstLaunchAt,
                       "firstLaunchAt must NOT change after the very first mark — it's an install-age stamp")
    }

    func test_markBootedAdvancesLastLaunchAt() {
        let dir = tempSupportDir()
        BootState.markBooted(in: dir)
        let firstLast = BootState.read(in: dir)?.lastLaunchAt
        // Need >1 second since the formatter uses second-level precision
        // by default. Sleep is cheap relative to the rest of the suite.
        Thread.sleep(forTimeInterval: 1.05)
        BootState.markBooted(in: dir)
        let secondLast = BootState.read(in: dir)?.lastLaunchAt
        XCTAssertNotNil(firstLast)
        XCTAssertNotNil(secondLast)
        XCTAssertNotEqual(firstLast, secondLast,
                          "lastLaunchAt must advance on subsequent marks")
    }

    func test_corruptMarkerStillCountsAsEverBooted() throws {
        let dir = tempSupportDir()
        let url = BootState.markerURL(in: dir)
        try Data("not valid json".utf8).write(to: url)
        XCTAssertTrue(BootState.everBooted(in: dir),
                      "Presence alone is the signal — a corrupt marker must still trigger the refuse-to-bootstrap guard")
        XCTAssertNil(BootState.read(in: dir),
                     "But the corrupt marker should fail to decode through read()")
    }

    func test_codableRoundTrip() throws {
        let state = BootState(firstLaunchAt: "2026-05-15T21:32:04Z",
                              lastLaunchAt:  "2026-05-15T22:00:00Z",
                              version: 1)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(BootState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    func test_legacyMarkerWithoutVersionDecodesAsV1() throws {
        let legacyJson = #"""
            {
                "firstLaunchAt": "2026-05-15T21:32:04Z",
                "lastLaunchAt":  "2026-05-15T22:00:00Z"
            }
            """#
        let data = legacyJson.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BootState.self, from: data)
        XCTAssertEqual(decoded.version, 1,
                       "Missing `version` must default to 1 — same backward-compat pattern AppSettings uses")
    }

    // MARK: - KeyStore.setupKeychainManaged guard

    @MainActor
    func test_setupKeychainManagedRefusesWhenMarkerExistsButSlotAbsent() throws {
        let dir = tempSupportDir()

        let store = KeyStore(supportDirectoryURL: dir)
        // Wipe first so the per-process keychain slot is clean.
        // Note: `resetAndWipe()` also clears the marker (intentional
        // — see the dedicated `test_resetAndWipeAlsoClearsBootStateMarker`)
        // so we must mark booted AFTER the wipe to set up the trap.
        store.resetAndWipe()
        BootState.markBooted(in: dir)

        // Re-construct so refreshState sees the clean keychain slot;
        // the marker presence is independent of keystore state.
        let freshStore = KeyStore(supportDirectoryURL: dir)
        XCTAssertEqual(freshStore.state, .notSetup)

        XCTAssertThrowsError(try freshStore.setupKeychainManaged()) { error in
            guard let kse = error as? KeyStore.KeyStoreError else {
                return XCTFail("Expected KeyStoreError, got \(error)")
            }
            XCTAssertEqual(kse, .everBootedButKeychainGone,
                           "Marker-present + slot-absent must throw everBootedButKeychainGone — this is the data-loss-trap guard")
        }
        XCTAssertEqual(freshStore.state, .notSetup,
                       "Refusal must leave the keystore in .notSetup so no fresh DEK was created")
    }

    @MainActor
    func test_setupKeychainManagedSucceedsOnFreshInstall() throws {
        let dir = tempSupportDir()
        // No marker: this is genuinely a first launch.
        XCTAssertFalse(BootState.everBooted(in: dir))

        let store = KeyStore(supportDirectoryURL: dir)
        store.resetAndWipe()
        XCTAssertEqual(store.state, .notSetup)

        XCTAssertNoThrow(try store.setupKeychainManaged())
        XCTAssertEqual(store.state, .unlocked,
                       "Fresh install without marker: bootstrap should succeed normally")

        // Cleanup — don't leak the test entry into the per-process
        // keychain stash.
        store.resetAndWipe()
    }

    @MainActor
    func test_resetAndWipeAlsoClearsBootStateMarker() {
        let dir = tempSupportDir()
        BootState.markBooted(in: dir)
        XCTAssertTrue(BootState.everBooted(in: dir))

        let store = KeyStore(supportDirectoryURL: dir)
        store.resetAndWipe()

        XCTAssertFalse(BootState.everBooted(in: dir),
                       "resetAndWipe must also remove the marker — otherwise a deliberate reset bounces back into the recovery screen on next launch")
    }

    // MARK: - RELEASE BLOCKER — Phase A.3

    /// **RELEASE BLOCKER — do not ship if this fails.**
    ///
    /// Reproduces the exact conditions of data-loss incident #4
    /// (2026-05-15) and asserts that PurpleLife refuses to silently
    /// generate a fresh DEK. The contract:
    ///
    /// 1. The install has run successfully before (`boot_state.json`
    ///    present in the support dir).
    /// 2. The Keychain slot for the install's DEK is genuinely
    ///    absent at bootstrap time.
    /// 3. `KeyStore.setupKeychainManaged()` is called.
    ///
    /// **Required outcome:**
    /// - The call throws `everBootedButKeychainGone`.
    /// - The keystore stays in `.notSetup` (no in-memory DEK).
    /// - The Keychain slot is **still absent** afterwards — no
    ///   fresh entry written. This is the load-bearing assertion:
    ///   if it ever fails, every prior-DEK-encrypted byte on disk
    ///   becomes unreadable forever and the recovery key / Time
    ///   Machine paths are foreclosed.
    ///
    /// If this test fails, the change being shipped has reintroduced
    /// the trap. Do not merge. See HANDOFF.md (2026-05-15) for the
    /// full incident log and the rationale behind every assertion.
    @MainActor
    func test_RELEASE_BLOCKER_dataLossTrapScenarioDoesNotCreateFreshDEK() throws {
        let dir = tempSupportDir()

        // === Set up the trap conditions ===
        let store = KeyStore(supportDirectoryURL: dir)
        // Wipe first so the per-process keychain slot is clean.
        store.resetAndWipe()
        // Then plant the marker as if the install had launched
        // successfully before. We re-construct the keystore so
        // refreshState sees a clean slate.
        BootState.markBooted(in: dir)
        XCTAssertTrue(BootState.everBooted(in: dir))

        let freshStore = KeyStore(supportDirectoryURL: dir)
        XCTAssertEqual(freshStore.state, .notSetup,
                       "Pre-condition: keystore must read as .notSetup (no entry in slot)")

        // === Run the bootstrap path ===
        var thrown: Error?
        do {
            try freshStore.setupKeychainManaged()
        } catch {
            thrown = error
        }

        // === Required outcome ===
        guard let kse = thrown as? KeyStore.KeyStoreError else {
            return XCTFail("RELEASE BLOCKER: setupKeychainManaged must throw a KeyStoreError; got \(String(describing: thrown))")
        }
        XCTAssertEqual(kse, .everBootedButKeychainGone,
                       "RELEASE BLOCKER: marker-present + slot-absent must throw everBootedButKeychainGone")

        XCTAssertEqual(freshStore.state, .notSetup,
                       "RELEASE BLOCKER: keystore must remain .notSetup — a transition to .unlocked here means a fresh DEK was created")

        // Strongest post-condition: the actual Keychain entry must
        // still be absent. If `cacheDEKInKeychain()` ran somewhere in
        // the refused path, this assertion catches it even if the
        // in-memory `state` looks clean.
        let postStatus = readKeychainStatus(for: freshStore)
        XCTAssertEqual(postStatus, .absent,
                       "RELEASE BLOCKER: the Keychain slot must STILL be absent after the refused bootstrap. " +
                       "A new entry here means we just made the user's data unrecoverable. " +
                       "Do not ship.")
    }

    /// Reflectively peek at the per-keystore Keychain entry status.
    /// We can't reach the private `keychainDEKAccount` directly from
    /// outside the type, but we *can* re-derive it via the same
    /// SHA-256 hash recipe — that's a stable contract documented in
    /// `KeyStore.init`. If the recipe ever changes, this test fails
    /// loudly and the maintainer gets to update both sides together.
    private func readKeychainStatus(for store: KeyStore) -> KeychainStore.EntryStatus {
        // Mirror of `KeyStore.init`'s recipe:
        //   pathHash = SHA-256(supportDirectory.path)
        //   account  = "dek-v1-\(pathHash)"
        // We don't have access to the support dir on the store, but
        // we passed it in to the constructor — caller is responsible
        // for using `tempSupportDir` consistently.
        // Practically: the trap test constructs the store against
        // `dir`, so we can re-pass `dir` here. To keep this helper
        // small and not thread an extra parameter, use a fixed
        // recipe re-derivation in the test's own scope. (See call
        // sites above.)
        let mirror = Mirror(reflecting: store)
        for child in mirror.children {
            if child.label == "keychainDEKAccount",
               let account = child.value as? String {
                return KeychainStore.entryStatus(for: account)
            }
        }
        XCTFail("Could not reflect keychainDEKAccount out of KeyStore — internal layout may have changed; update this test")
        return .absent
    }
}
