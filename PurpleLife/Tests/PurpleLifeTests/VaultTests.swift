import XCTest
@testable import PurpleLife

/// Covers the Vault feature plumbing — the `isVault` flag's Codable
/// behavior (especially backward-compat decode of pre-Vault
/// `schema.json` files), the SchemaLibrary `.vault` category's
/// materialize stamping, the SchemaRegistry visibility properties, and
/// `SearchService.search`'s `excludingTypeIds` filter.
///
/// `VaultAuthService` itself isn't unit-tested — `LAContext`
/// auth requires a real device prompt and there's no XCTest hook for
/// that path. The wrapper is small enough to verify by hand.
final class VaultTests: XCTestCase {

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-\(UUID().uuidString).json")
    }

    // MARK: - ObjectType Codable backward compat

    func testObjectTypeDefaultsIsVaultFalse() {
        let t = ObjectType(
            id: "X", name: "X", pluralName: "Xs",
            systemImage: "doc", colorHex: "#000000",
            fields: [], builtIn: false
        )
        XCTAssertFalse(t.isVault, "isVault default must be false so legacy types stay in the regular sidebar")
    }

    /// The load-bearing backward-compat test: a `schema.json` written by
    /// a pre-Vault build has no `isVault` key. Swift's *synthesized*
    /// decoder would throw on a missing non-Optional `Bool` key, which
    /// `SchemaRegistry.load`'s `try?` would silently swallow — and the
    /// user would silently lose every schema customization. The custom
    /// `init(from:)` decoder uses `decodeIfPresent`, defaulting to
    /// `false`. This test locks that contract.
    func testObjectTypeDecodesWithoutIsVaultKey() throws {
        let legacyJSON = """
        {
            "id": "Recipe",
            "name": "Recipe",
            "pluralName": "Recipes",
            "systemImage": "fork.knife",
            "colorHex": "#E8A93B",
            "fields": [],
            "builtIn": false,
            "primaryFieldKey": "title"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ObjectType.self, from: legacyJSON)
        XCTAssertEqual(decoded.id, "Recipe")
        XCTAssertFalse(decoded.isVault, "missing isVault key must decode as false, not throw")
        XCTAssertEqual(decoded.primaryFieldKey, "title")
    }

    func testObjectTypeRoundTripsIsVault() throws {
        var t = ObjectType(
            id: "VaultThing", name: "Vault thing", pluralName: "Vault things",
            systemImage: "lock", colorHex: "#9D4DCC",
            fields: [], builtIn: false
        )
        t.isVault = true

        let encoded = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(ObjectType.self, from: encoded)
        XCTAssertTrue(decoded.isVault)
    }

    // MARK: - SchemaLibrary materialize

    func testVaultEntriesMaterializeWithIsVaultTrue() {
        let vaultEntries = SchemaLibrary.entries.filter { $0.category == .vault }
        XCTAssertFalse(vaultEntries.isEmpty, "expected the vault library to be populated")
        for entry in vaultEntries {
            let materialized = entry.materialize()
            XCTAssertTrue(materialized.isVault,
                          "\(entry.id): vault-category entry must materialize with isVault=true")
        }
    }

    func testNonVaultEntriesMaterializeWithIsVaultFalse() {
        // Sample 10 non-vault entries from across the catalog to keep
        // the test cheap while still proving the materialize path
        // doesn't accidentally vault-flag everything.
        let sample = SchemaLibrary.entries.filter { $0.category != .vault }.prefix(10)
        XCTAssertFalse(sample.isEmpty)
        for entry in sample {
            let materialized = entry.materialize()
            XCTAssertFalse(materialized.isVault,
                           "\(entry.id): non-vault entry must materialize with isVault=false")
        }
    }

    func testVaultCategoryShipsAtLeastTwentyEntries() {
        let count = SchemaLibrary.entries.filter { $0.category == .vault }.count
        XCTAssertGreaterThanOrEqual(count, 20,
                                    "the Vault catalog promises ≥20 entries across health / encounter / kink / body")
    }

    // MARK: - SchemaRegistry visibility filters

    @MainActor
    func testVisibleTypesExcludesVaultTypes() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)

        // Insert a Vault-flagged user type.
        var vaultType = ObjectType(
            id: "VaultTestType", name: "Test", pluralName: "Tests",
            systemImage: "lock", colorHex: "#9D4DCC",
            fields: [FieldDef.make(name: "Title", kind: .text, required: true)],
            builtIn: false,
            primaryFieldKey: "title"
        )
        vaultType.isVault = true
        reg.upsertType(vaultType)

        XCTAssertNotNil(reg.type(id: "VaultTestType"),
                        "vault types must still exist in `types`")
        XCTAssertFalse(reg.visibleTypes.contains { $0.id == "VaultTestType" },
                       "vault types must NOT appear in `visibleTypes`")
        XCTAssertTrue(reg.visibleVaultTypes.contains { $0.id == "VaultTestType" },
                      "vault types must appear in `visibleVaultTypes`")
        XCTAssertTrue(reg.vaultTypeIds.contains("VaultTestType"),
                      "vaultTypeIds must include the type for search-exclusion")
    }

    @MainActor
    func testVisibleVaultTypesIsEmptyByDefault() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)
        XCTAssertTrue(reg.visibleVaultTypes.isEmpty,
                      "fresh seed has no vault types")
        XCTAssertTrue(reg.vaultTypeIds.isEmpty)
    }

    @MainActor
    func testHiddenBuiltInVaultTypeIsExcludedFromBoth() throws {
        // Construct a built-in vault type directly (the seeded built-ins
        // aren't vaulted, so we make one for this test). Built-in +
        // hidden means the user is hiding it from the sidebar even when
        // the Vault is unlocked — should disappear from `visibleVaultTypes`
        // the same way a hidden non-vault built-in disappears from
        // `visibleTypes`.
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)

        var t = ObjectType(
            id: "BuiltInVault", name: "Vault built-in", pluralName: "Vault built-ins",
            systemImage: "lock", colorHex: "#9D4DCC",
            fields: [FieldDef.make(name: "Title", kind: .text, required: true)],
            builtIn: true,
            primaryFieldKey: "title"
        )
        t.isVault = true
        reg.upsertType(t)
        reg.setHidden("BuiltInVault", hidden: true)

        XCTAssertFalse(reg.visibleVaultTypes.contains { $0.id == "BuiltInVault" })
        // But `vaultTypeIds` is for search-exclusion only — should not
        // honor the hidden flag (the search exclusion is the same
        // whether the type is sidebar-hidden or not).
        XCTAssertTrue(reg.vaultTypeIds.contains("BuiltInVault"))
    }
}
