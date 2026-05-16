import XCTest
@testable import PurpleLife

/// Coverage for the schema-editor additions in this release:
/// `SchemaRegistry.setVault`, `SchemaRegistry.setTypeTags`,
/// `ObjectType.tags` Codable backward-compat, and
/// `TagService.effectiveTagIds(for:in:)`'s merge / dedupe contract.
final class VaultToggleAndTypeTagsTests: XCTestCase {

    private func tempSchemaFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-vt-\(UUID().uuidString).json")
    }

    // MARK: - SchemaRegistry.setVault

    @MainActor
    func testSetVaultFlipsFlagAndMovesTypeBetweenVisibilitySets() throws {
        let url = tempSchemaFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)

        let custom = ObjectType(
            id: "CustomThing", name: "Custom thing", pluralName: "Custom things",
            systemImage: "doc", colorHex: "#999999",
            fields: [FieldDef.make(name: "Title", kind: .text, required: true)],
            builtIn: false,
            primaryFieldKey: "title"
        )
        reg.upsertType(custom)

        XCTAssertTrue(reg.visibleTypes.contains { $0.id == "CustomThing" })
        XCTAssertFalse(reg.visibleVaultTypes.contains { $0.id == "CustomThing" })

        reg.setVault("CustomThing", isVault: true)

        XCTAssertTrue(reg.type(id: "CustomThing")?.isVault == true)
        XCTAssertFalse(reg.visibleTypes.contains { $0.id == "CustomThing" },
                       "vault-flagged type must drop out of visibleTypes")
        XCTAssertTrue(reg.visibleVaultTypes.contains { $0.id == "CustomThing" })
        XCTAssertTrue(reg.vaultTypeIds.contains("CustomThing"))

        reg.setVault("CustomThing", isVault: false)

        XCTAssertFalse(reg.type(id: "CustomThing")?.isVault ?? true)
        XCTAssertTrue(reg.visibleTypes.contains { $0.id == "CustomThing" })
        XCTAssertFalse(reg.visibleVaultTypes.contains { $0.id == "CustomThing" })
    }

    @MainActor
    func testSetVaultOnUnknownTypeIsNoOp() throws {
        let url = tempSchemaFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)
        let snapshot = reg.types
        reg.setVault("NotAnId", isVault: true)
        XCTAssertEqual(reg.types.map(\.id), snapshot.map(\.id),
                       "setVault on missing id must not mutate the registry")
    }

    @MainActor
    func testSetVaultIsIdempotentWhenAlreadyAtTarget() throws {
        let url = tempSchemaFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)

        var t = ObjectType(
            id: "AlreadyVault", name: "Already", pluralName: "Alreadies",
            systemImage: "lock", colorHex: "#9D4DCC",
            fields: [FieldDef.make(name: "Title", kind: .text, required: true)],
            builtIn: false,
            primaryFieldKey: "title"
        )
        t.isVault = true
        reg.upsertType(t)
        let beforeUpdatedAt = reg.type(id: "AlreadyVault")?.updatedAt
        // Second call to setVault(true) on an already-vault type should
        // early-return and not bump updatedAt — otherwise every
        // re-render would cause a churn write + CloudKit push.
        reg.setVault("AlreadyVault", isVault: true)
        let afterUpdatedAt = reg.type(id: "AlreadyVault")?.updatedAt
        XCTAssertEqual(beforeUpdatedAt, afterUpdatedAt,
                       "setVault to the same value must not stamp updatedAt")
    }

    // MARK: - SchemaRegistry.setTypeTags

    @MainActor
    func testSetTypeTagsReplacesListAndDedupes() throws {
        let url = tempSchemaFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)

        let custom = ObjectType(
            id: "Tagged", name: "Tagged", pluralName: "Taggeds",
            systemImage: "doc", colorHex: "#999999",
            fields: [FieldDef.make(name: "Title", kind: .text, required: true)],
            builtIn: false,
            primaryFieldKey: "title"
        )
        reg.upsertType(custom)

        // First write — order preserved.
        reg.setTypeTags(["a", "b", "c"], onTypeId: "Tagged")
        XCTAssertEqual(reg.type(id: "Tagged")?.tags, ["a", "b", "c"])

        // Dedupe — input has duplicates, output keeps first occurrence
        // and preserves declared order.
        reg.setTypeTags(["x", "y", "x", "z", "y"], onTypeId: "Tagged")
        XCTAssertEqual(reg.type(id: "Tagged")?.tags, ["x", "y", "z"])

        // Empty list clears.
        reg.setTypeTags([], onTypeId: "Tagged")
        XCTAssertEqual(reg.type(id: "Tagged")?.tags, [])
    }

    @MainActor
    func testSetTypeTagsOnUnknownTypeIsNoOp() throws {
        let url = tempSchemaFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)
        // No throw, no crash.
        reg.setTypeTags(["a"], onTypeId: "NoSuchType")
    }

    // MARK: - ObjectType.tags Codable backward compat

    func testObjectTypeDecodesLegacySchemaWithoutTagsKey() throws {
        // Pre-tags-on-types `schema.json` files have no `tags` key on
        // each type. The synthesized decoder would throw on missing
        // non-Optional `[String]`; our custom `init(from:)` uses
        // `decodeIfPresent`, defaulting to `[]`. This test locks
        // that contract — without it, every existing user's schema
        // would fail to decode and the registry would reseed.
        let legacyJSON = """
        {
            "id": "Recipe",
            "name": "Recipe",
            "pluralName": "Recipes",
            "systemImage": "fork.knife",
            "colorHex": "#E8A93B",
            "fields": [],
            "builtIn": false,
            "primaryFieldKey": "title",
            "isVault": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ObjectType.self, from: legacyJSON)
        XCTAssertEqual(decoded.id, "Recipe")
        XCTAssertEqual(decoded.tags, [], "missing tags key must decode as empty array")
    }

    func testObjectTypeRoundTripsTags() throws {
        var t = ObjectType(
            id: "T", name: "T", pluralName: "Ts",
            systemImage: "doc", colorHex: "#000000",
            fields: [], builtIn: false
        )
        t.tags = ["alpha", "beta"]
        let encoded = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(ObjectType.self, from: encoded)
        XCTAssertEqual(decoded.tags, ["alpha", "beta"])
    }

    // MARK: - TagService.effectiveTagIds merge + dedupe

    @MainActor
    func testEffectiveTagIdsMergesTypeAndRecordTagsDeduped() throws {
        // Set up a SettingsStore so TagService.allTags has a usable
        // vocabulary — effectiveTagIds itself doesn't read the
        // vocabulary, but resolved helpers (`effectiveTags`) do.
        let store = SettingsStore()
        store.settings.tagVocabulary = []
        store.save()
        TagService.settings = store
        defer { TagService.settings = nil }

        let type = ObjectType(
            id: "TaggyType", name: "Taggy", pluralName: "Taggys",
            systemImage: "doc", colorHex: "#999999",
            fields: [FieldDef.make(name: "Title", kind: .text, required: true)],
            builtIn: false,
            primaryFieldKey: "title",
            tags: ["tag-a", "tag-b"]
        )

        // Record carries its own tags AND duplicates one of the
        // type-scope ids — that duplicate must collapse, and the
        // type-scope id keeps its earlier position.
        let record = ObjectRecord.make(
            typeId: type.id,
            fields: [TagDef.recordKey: ["tag-c", "tag-b", "tag-d"]]
        )

        let effective = TagService.effectiveTagIds(for: record, in: type)
        XCTAssertEqual(effective, ["tag-a", "tag-b", "tag-c", "tag-d"],
                       "type-scope ids come first, per-record ids follow, duplicates collapse with first wins")
    }

    @MainActor
    func testEffectiveTagIdsWithEmptyRecordReturnsOnlyTypeTags() throws {
        let store = SettingsStore()
        store.settings.tagVocabulary = []
        store.save()
        TagService.settings = store
        defer { TagService.settings = nil }

        let type = ObjectType(
            id: "OnlyTypeTags", name: "T", pluralName: "Ts",
            systemImage: "doc", colorHex: "#000000",
            fields: [FieldDef.make(name: "Title", kind: .text, required: true)],
            builtIn: false,
            primaryFieldKey: "title",
            tags: ["only-from-type"]
        )

        let record = ObjectRecord.make(typeId: type.id, fields: [:])
        XCTAssertEqual(TagService.effectiveTagIds(for: record, in: type), ["only-from-type"])
    }

    @MainActor
    func testEffectiveTagIdsWithNoTagsAnywhereReturnsEmpty() throws {
        let store = SettingsStore()
        store.settings.tagVocabulary = []
        store.save()
        TagService.settings = store
        defer { TagService.settings = nil }

        let type = ObjectType(
            id: "Bare", name: "Bare", pluralName: "Bares",
            systemImage: "doc", colorHex: "#000000",
            fields: [FieldDef.make(name: "Title", kind: .text, required: true)],
            builtIn: false,
            primaryFieldKey: "title"
        )
        let record = ObjectRecord.make(typeId: type.id, fields: [:])
        XCTAssertEqual(TagService.effectiveTagIds(for: record, in: type), [])
    }
}
