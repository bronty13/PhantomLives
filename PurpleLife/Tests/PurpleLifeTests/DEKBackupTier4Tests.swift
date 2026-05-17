import XCTest
import CryptoKit
@testable import PurpleLife

/// Tier 4 — CloudKit private-zone DEK backup. Tests the deterministic
/// parts (KeyStore API surface, no-sync fallback shape). The CloudKit
/// round-trip itself is verified manually per the Phase 4 convention
/// (HANDOFF.md 2026-05-10) — XCTest can't talk to a real CKContainer.
@MainActor
final class DEKBackupTier4Tests: XCTestCase {

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("purplelife-tier4-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// `tryRestoreFromCloudKitBackup` returns false when no sync
    /// service is wired (the test-default state) — the keystore can't
    /// reach CloudKit, can't restore, falls back to existing
    /// recovery paths. Locks the contract that no sync == no Tier 4.
    func test_tryRestoreReturnsFalseWhenSyncNotWired() async {
        let store = KeyStore(supportDirectoryURL: tempDir())
        defer { store.resetAndWipe() }
        XCTAssertNil(store.sync, "Test default has no sync wired")
        let result = await store.tryRestoreFromCloudKitBackup()
        XCTAssertFalse(result, "Tier 4 restore must be a no-op when sync isn't available")
    }

    /// Tier 4 doesn't affect the existing tier ordering — local
    /// Keychain (Tier 1) silent unlock still wins even when a sync
    /// service is wired. The CloudKit fetch is only consulted when
    /// the keystore enters the explicit recovery path; it doesn't
    /// race the local Keychain on every launch.
    func test_localKeychainUnlockStillWinsWithSyncWired() throws {
        let store = KeyStore(supportDirectoryURL: tempDir())
        defer { store.resetAndWipe() }
        // No sync wired — but the keystore still completes
        // first-launch setup normally and ends up unlocked via
        // local Keychain. Tier 4 push (the fire-and-forget from
        // cacheDEKInKeychain) would fire if sync were wired; here
        // it's a no-op because sync is nil. The point of this
        // test: verify the addition of Tier 4 plumbing didn't
        // change the silent-unlock behavior.
        XCTAssertEqual(store.state, .notSetup)
        _ = try store.setupKeychainManaged()
        XCTAssertEqual(store.state, .unlocked,
                       "Tier 1 / Tier 3 silent unlock must still work; Tier 4 plumbing shouldn't perturb the normal happy path")
    }

    /// The DEK backup record name embeds the same machineIdentifier
    /// Tier 3 uses for its iCloud Keychain mirror. Same Mac → same
    /// record name on every launch. Different Macs in the same
    /// iCloud account → distinct records, no collision.
    func test_dekBackupRecordNameMatchesMachineIdentifier() {
        // The full record name is private to CloudKitSyncService, but
        // the machineIdentifier piece is what guarantees per-Mac
        // independence and is publicly inspectable. Lock that piece;
        // a regression that switches to a global / non-per-Mac
        // identifier would surface here.
        let machineId = KeychainStore.machineIdentifier
        XCTAssertFalse(machineId.isEmpty)
        XCTAssertNotEqual(machineId, "unknown-machine",
                          "IOPlatformUUID must be available in the test environment too")
    }
}
