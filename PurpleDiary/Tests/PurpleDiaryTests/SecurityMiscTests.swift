import XCTest
import GRDB
import LocalAuthentication
@testable import PurpleDiary

final class SecurityMiscTests: XCTestCase {

    /// The biometric policy mapping is the testability seam for the lock screen
    /// (the actual `LAContext` prompt has no XCTest hook).
    @MainActor
    func testBiometricPolicyMapping() {
        XCTAssertEqual(BiometricAuthService.policy(biometryOnly: false), .deviceOwnerAuthentication)
        XCTAssertEqual(BiometricAuthService.policy(biometryOnly: true), .deviceOwnerAuthenticationWithBiometrics)
    }

    /// Immutability guard: the set of shipped migrations is frozen. Editing or
    /// renaming `v1_initial` would change the GRDB migration hash and brick
    /// every existing (now SQLCipher-encrypted) install at launch. When you add
    /// a NEW migration, append its identifier here deliberately — never touch a
    /// shipped one.
    @MainActor
    func testShippedMigrationsAreFrozen() throws {
        let queue = try DatabaseQueue()
        try DatabaseService.applyMigrations(to: queue)
        let ids = try queue.read {
            try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
        }
        XCTAssertEqual(ids, ["v1_initial", "v2_trackers", "v3_attachments", "v4_journals", "v5_templates", "v6_vault", "v7_journal_settings"],
                       "Shipped migrations are immutable. Append new identifiers here when you add a migration; never edit or rename an existing one.")
    }
}
