import XCTest
@testable import PurpleLife

/// Phase 2 schema layer — confirms the seed loads, persists, and the
/// load-then-merge logic doesn't lose user edits when new built-ins
/// are added in a later release.
final class SchemaRegistryTests: XCTestCase {

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-\(UUID().uuidString).json")
    }

    @MainActor
    func testSeedsBuiltInsOnFirstLaunch() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)

        XCTAssertFalse(reg.types.isEmpty)
        XCTAssertNotNil(reg.type(id: "Person"))
        XCTAssertNotNil(reg.type(id: "Book"))
        XCTAssertNotNil(reg.type(id: "Camera"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "First launch should persist the seeded schema")
    }

    @MainActor
    func testHidingBuiltInDoesNotDeleteIt() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)

        reg.setHidden("Person", hidden: true)
        XCTAssertNotNil(reg.type(id: "Person"),
                        "Hidden built-ins must still exist in `types`")
        XCTAssertFalse(reg.visibleTypes.contains { $0.id == "Person" },
                       "Hidden built-ins must be excluded from `visibleTypes`")

        reg.setHidden("Person", hidden: false)
        XCTAssertTrue(reg.visibleTypes.contains { $0.id == "Person" })
    }

    @MainActor
    func testDeleteRefusesBuiltIns() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)

        let removed = reg.deleteType(id: "Person")
        XCTAssertFalse(removed, "Built-ins must not be deletable")
        XCTAssertNotNil(reg.type(id: "Person"))
    }

    @MainActor
    func testUpsertAddsAndUpdatesUserType() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)

        let custom = ObjectType(
            id: "Recipe",
            name: "Recipe",
            pluralName: "Recipes",
            systemImage: "fork.knife",
            colorHex: "#E8A93B",
            fields: [FieldDef.make(name: "Title", kind: .text, required: true)],
            builtIn: false,
            primaryFieldKey: "title",
            kanbanGroupKey: nil,
            calendarDateKey: nil,
            galleryAttachmentKey: nil
        )
        reg.upsertType(custom)
        XCTAssertNotNil(reg.type(id: "Recipe"))

        var renamed = custom
        renamed.pluralName = "Cookbook"
        reg.upsertType(renamed)
        XCTAssertEqual(reg.type(id: "Recipe")?.pluralName, "Cookbook")

        XCTAssertTrue(reg.deleteType(id: "Recipe"),
                       "User-defined types must be deletable")
        XCTAssertNil(reg.type(id: "Recipe"))
    }

    @MainActor
    func testFieldMutations() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)

        let newField = FieldDef.make(name: "Nickname", kind: .text)
        reg.addField(newField, toTypeId: "Person")
        XCTAssertNotNil(reg.type(id: "Person")?.field(forKey: newField.key))

        var renamed = newField
        renamed.name = "Handle"
        reg.updateField(renamed, onTypeId: "Person")
        XCTAssertEqual(reg.type(id: "Person")?.field(forKey: newField.key)?.name, "Handle")

        reg.removeField(fieldId: newField.id, fromTypeId: "Person")
        XCTAssertNil(reg.type(id: "Person")?.field(forKey: newField.key))
    }

    @MainActor
    func testReloadPicksUpDiskState() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let first = SchemaRegistry(fileURL: url)
        first.setHidden("Person", hidden: true)
        let custom = ObjectType(
            id: "Recipe",
            name: "Recipe", pluralName: "Recipes",
            systemImage: "fork.knife", colorHex: "#E8A93B",
            fields: [], builtIn: false,
            primaryFieldKey: nil, kanbanGroupKey: nil,
            calendarDateKey: nil, galleryAttachmentKey: nil
        )
        first.upsertType(custom)

        // Fresh instance reads the saved file.
        let second = SchemaRegistry(fileURL: url)
        XCTAssertNotNil(second.type(id: "Recipe"))
        XCTAssertTrue(second.hiddenBuiltInIds.contains("Person"))
        XCTAssertFalse(second.visibleTypes.contains { $0.id == "Person" })
    }
}
