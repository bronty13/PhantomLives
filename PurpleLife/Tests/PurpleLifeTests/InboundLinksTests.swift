import XCTest
@testable import PurpleLife

/// `ObjectEngine.recordsLinkingTo` — reverse-of-link helper that
/// powers the detail view's "Linked from" rail. Inserts a couple of
/// records, links one to the other via a `.link` field, and confirms
/// the linker shows up.
final class InboundLinksTests: XCTestCase {

    @MainActor
    func testRecordsLinkingToFindsTheLinker() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-inbound-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let schema = SchemaRegistry(fileURL: url)

        // Use a fresh user-defined type so we don't collide with seeded
        // built-ins or other tests' fixtures.
        let nameField = FieldDef(id: "f-name", key: "name", name: "Name",
                                 kind: .text, options: [], required: false, description: nil)
        let linkField = FieldDef(id: "f-target", key: "target", name: "Target",
                                 kind: .link, options: [], required: false, description: nil)
        let target = ObjectType(
            id: "test-target-\(UUID().uuidString)",
            name: "Target", pluralName: "Targets",
            systemImage: "circle", colorHex: "#000000",
            fields: [nameField], builtIn: false,
            primaryFieldKey: "name", kanbanGroupKey: nil,
            calendarDateKey: nil, galleryAttachmentKey: nil,
            updatedAt: nil
        )
        let linker = ObjectType(
            id: "test-linker-\(UUID().uuidString)",
            name: "Linker", pluralName: "Linkers",
            systemImage: "square", colorHex: "#000000",
            fields: [nameField, linkField], builtIn: false,
            primaryFieldKey: "name", kanbanGroupKey: nil,
            calendarDateKey: nil, galleryAttachmentKey: nil,
            updatedAt: nil
        )
        schema.upsertType(target)
        schema.upsertType(linker)

        // Set ObjectEngine's currentSchema so the FTS hook on create
        // can resolve types — not strictly required for this test
        // but matches production wiring.
        ObjectEngine.currentSchema = schema

        let targetRecord = try ObjectEngine.create(typeId: target.id, fields: ["name": "I am the target"])
        let linkerRecord = try ObjectEngine.create(typeId: linker.id, fields: [
            "name": "I link",
            "target": targetRecord.id,
        ])
        let unrelated = try ObjectEngine.create(typeId: linker.id, fields: [
            "name": "I link elsewhere",
            "target": "some-other-id",
        ])
        defer {
            try? ObjectEngine.delete(id: targetRecord.id)
            try? ObjectEngine.delete(id: linkerRecord.id)
            try? ObjectEngine.delete(id: unrelated.id)
        }

        let inbound = try ObjectEngine.recordsLinkingTo(recordId: targetRecord.id, schema: schema)
        XCTAssertEqual(inbound.count, 1, "exactly one record links to the target")
        XCTAssertEqual(inbound.first?.record.id, linkerRecord.id,
                       "the inbound record should be the one whose target matches")
        XCTAssertEqual(inbound.first?.type.id, linker.id)
    }

    @MainActor
    func testRecordsLinkingToReturnsEmptyForUnreferenced() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-inbound-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let schema = SchemaRegistry(fileURL: url)
        let inbound = try ObjectEngine.recordsLinkingTo(
            recordId: "definitely-not-a-real-id-\(UUID().uuidString)",
            schema: schema
        )
        XCTAssertTrue(inbound.isEmpty)
    }
}
