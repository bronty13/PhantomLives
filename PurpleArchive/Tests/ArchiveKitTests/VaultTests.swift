import XCTest
@testable import ArchiveKit

final class VaultTests: XCTestCase {

    func testInMemoryRoundTrip() {
        let vault = InMemoryVault()
        XCTAssertNil(vault.password(for: "a.zip"))
        vault.setPassword("secret", for: "a.zip")
        XCTAssertEqual(vault.password(for: "a.zip"), "secret")
        XCTAssertEqual(vault.storedKeys(), ["a.zip"])
        vault.removePassword(for: "a.zip")
        XCTAssertNil(vault.password(for: "a.zip"))
        XCTAssertTrue(vault.storedKeys().isEmpty)
    }

    func testKeyDerivationByFilename() {
        let vault = InMemoryVault()
        let a = URL(fileURLWithPath: "/Users/x/Downloads/photos.zip")
        let b = URL(fileURLWithPath: "/Volumes/USB/photos.zip")   // same name, moved
        vault.setPassword("pw", for: a)
        XCTAssertEqual(vault.password(for: b), "pw", "filename keying survives a move")
        XCTAssertEqual(vault.key(for: a), "photos.zip")
    }

    /// The real Keychain works on a logged-in session; in headless CI SecItem
    /// can fail (errSecMissingEntitlement / no keychain). Skip gracefully then.
    func testKeychainRoundTripIfAvailable() throws {
        let vault = KeychainVault(service: "com.bronty13.PurpleArchive.vault.test")
        let key = "unit-test-\(UUID().uuidString).zip"
        vault.setPassword("kc-secret", for: key)
        let read = vault.password(for: key)
        defer { vault.removePassword(for: key) }
        try XCTSkipIf(read == nil, "Keychain unavailable in this environment")
        XCTAssertEqual(read, "kc-secret")
        vault.removePassword(for: key)
        XCTAssertNil(vault.password(for: key))
    }
}
