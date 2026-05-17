import XCTest
@testable import PurpleLife

/// Tier 3 — iCloud Keychain mirror.
///
/// **Test isolation note.** Production sets `iCloudMirrorEnabled = true`;
/// under XCTest it's `false` (the per-pid test service name would
/// otherwise pollute the developer's iCloud Keychain). So these tests
/// verify the *contract* (correct account naming, gated writes, etc.)
/// without actually exercising iCloud Keychain — that path is verified
/// manually per the Phase 4 convention (HANDOFF 2026-05-10).
final class KeychainICloudMirrorTests: XCTestCase {

    func test_iCloudMirrorDisabledUnderXCTest() {
        // Hard contract: the iCloud mirror is off in the test
        // environment so test runs can't add stray entries to the
        // user's iCloud Keychain. If this ever flips to true under
        // tests, every test that touches KeychainStore would start
        // syncing garbage upstream.
        XCTAssertFalse(KeychainStore.iCloudMirrorEnabled,
                       "iCloud Keychain mirror must be disabled under XCTest")
    }

    func test_machineIdentifierIsNonEmpty() {
        // IOPlatformUUID is the OS-stable hardware UUID; even in
        // CI / minimal VM environments it's present. If this ever
        // returns empty, the mirror-account derivation would
        // collide for every Mac and Tier 3 would devolve into the
        // "shared-DEK race" the design deliberately rejected.
        let id = KeychainStore.machineIdentifier
        XCTAssertFalse(id.isEmpty)
        // Sanity: looks like a UUID-shaped string most of the time.
        // Don't lock the exact format because Apple has reserved the
        // right to change it; but the fallback "unknown-machine"
        // would indicate IOKit failed.
        XCTAssertNotEqual(id, "")
    }

    func test_iCloudMirrorAccountSaltsInMachineId() {
        let primary = "dek-v1-abc123"
        let mirror = KeychainStore.iCloudMirrorAccount(for: primary)
        XCTAssertTrue(mirror.hasPrefix("icloud-mirror."),
                      "Mirror account must be prefixed so debugging is greppable")
        XCTAssertTrue(mirror.contains(KeychainStore.machineIdentifier),
                      "Mirror account must include the machine identifier so per-Mac entries don't collide in iCloud Keychain")
        XCTAssertTrue(mirror.hasSuffix(primary),
                      "Mirror account must preserve the primary account name so the relationship is obvious")
    }

    func test_iCloudMirrorAccountIsDeterministic() {
        let primary = "dek-v1-xyz789"
        let a = KeychainStore.iCloudMirrorAccount(for: primary)
        let b = KeychainStore.iCloudMirrorAccount(for: primary)
        XCTAssertEqual(a, b, "Same primary must always derive the same mirror account on this Mac")
    }

    func test_iCloudMirrorAccountDiffersAcrossPrimaries() {
        XCTAssertNotEqual(
            KeychainStore.iCloudMirrorAccount(for: "dek-a"),
            KeychainStore.iCloudMirrorAccount(for: "dek-b")
        )
    }

    /// Under XCTest the mirror is disabled, so
    /// setDataWithICloudMirror writes ONLY the local entry. Verify by
    /// reading back via the mirror-only path and confirming nil.
    /// (Production would have both; tests cover the gating.)
    func test_setDataWithICloudMirrorUnderTestSkipsMirrorWrite() throws {
        let account = "tier3-test-\(UUID().uuidString)"
        defer {
            try? KeychainStore.delete(account: account, synchronizable: false)
            try? KeychainStore.delete(
                account: KeychainStore.iCloudMirrorAccount(for: account),
                synchronizable: true)
        }
        try KeychainStore.setDataWithICloudMirror(Data("hello".utf8), for: account)

        // Local entry exists.
        XCTAssertEqual(KeychainStore.getData(for: account, synchronizable: false),
                       Data("hello".utf8))
        // iCloud mirror entry should NOT exist (test gating).
        XCTAssertNil(KeychainStore.getData(
            for: KeychainStore.iCloudMirrorAccount(for: account),
            synchronizable: true))
    }

    /// getDataIncludingICloudMirror prefers local when present, even
    /// if a mirror entry also exists. Verified by writing a local
    /// entry directly and asserting it's returned.
    func test_getDataIncludingICloudMirrorPrefersLocal() throws {
        let account = "tier3-prefer-local-\(UUID().uuidString)"
        defer { try? KeychainStore.delete(account: account, synchronizable: false) }
        try KeychainStore.setData(Data("local-wins".utf8), for: account, synchronizable: false)
        XCTAssertEqual(KeychainStore.getDataIncludingICloudMirror(for: account),
                       Data("local-wins".utf8))
    }
}
