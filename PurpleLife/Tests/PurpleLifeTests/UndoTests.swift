import XCTest
@testable import PurpleLife

/// Undo / redo across `ObjectEngine` mutations and `SchemaRegistry`
/// mutations. Uses a fixture `UndoManager` (rather than the
/// SwiftUI environment one) so the tests don't need a UI host.
///
/// Pattern: assign the fixture manager, perform the mutation, call
/// `undo()`, assert the inverse happened. For redo: `undo()` then
/// `redo()` and assert the original state.
final class UndoTests: XCTestCase {

    @MainActor
    private func freshUndo() -> UndoManager {
        let m = UndoManager()
        ObjectEngine.undoManager = m
        return m
    }

    @MainActor
    private func freshSchema() -> SchemaRegistry {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-undo-\(UUID().uuidString).json")
        return SchemaRegistry(fileURL: url)
    }

    // MARK: - ObjectEngine create / undo / redo

    @MainActor
    func testCreateThenUndoRemovesTheRecord() throws {
        let m = freshUndo()
        let typeId = "test-create-\(UUID().uuidString)"

        let record = try ObjectEngine.create(typeId: typeId)
        XCTAssertNotNil(try DatabaseService.shared.fetchObject(id: record.id),
                        "record should exist after create")

        XCTAssertTrue(m.canUndo)
        m.undo()
        XCTAssertNil(try DatabaseService.shared.fetchObject(id: record.id),
                     "undo of create should delete the record")
    }

    @MainActor
    func testCreateUndoRedoRestoresWithSameId() throws {
        let m = freshUndo()
        let typeId = "test-redo-\(UUID().uuidString)"

        let record = try ObjectEngine.create(typeId: typeId, fields: ["k": "v"])
        let originalId = record.id
        m.undo()
        XCTAssertTrue(m.canRedo, "undo should leave a redo on the stack")
        m.redo()

        let restored = try DatabaseService.shared.fetchObject(id: originalId)
        XCTAssertNotNil(restored, "redo should re-create with original id")
        XCTAssertEqual(restored?.fields()["k"] as? String, "v",
                       "redo should restore the original fields")
    }

    // MARK: - ObjectEngine update / undo

    @MainActor
    func testUpdateThenUndoRestoresPriorFields() throws {
        let m = freshUndo()
        let typeId = "test-update-\(UUID().uuidString)"

        let original = try ObjectEngine.create(typeId: typeId, fields: ["color": "red"])
        defer { try? DatabaseService.shared.deleteObject(id: original.id) }
        // Reset undo so the undo for create doesn't run before our
        // update-undo target.
        m.removeAllActions()

        _ = try ObjectEngine.update(original, fields: ["color": "blue"])
        XCTAssertEqual(
            try DatabaseService.shared.fetchObject(id: original.id)?.fields()["color"] as? String,
            "blue"
        )

        m.undo()
        XCTAssertEqual(
            try DatabaseService.shared.fetchObject(id: original.id)?.fields()["color"] as? String,
            "red",
            "undo of update should restore the prior field value"
        )
    }

    // MARK: - ObjectEngine delete / undo

    @MainActor
    func testDeleteThenUndoRecreatesWithSameIdAndFields() throws {
        let m = freshUndo()
        let typeId = "test-delete-\(UUID().uuidString)"

        let r = try ObjectEngine.create(typeId: typeId, fields: ["title": "Doomed"])
        let originalId = r.id
        m.removeAllActions()

        try ObjectEngine.delete(id: r.id)
        XCTAssertNil(try DatabaseService.shared.fetchObject(id: originalId))

        m.undo()
        let restored = try DatabaseService.shared.fetchObject(id: originalId)
        XCTAssertNotNil(restored, "undo of delete should restore at the original id")
        XCTAssertEqual(restored?.fields()["title"] as? String, "Doomed",
                       "undo of delete should restore the original fields")

        // Cleanup
        try? DatabaseService.shared.deleteObject(id: originalId)
    }

    // MARK: - SchemaRegistry undo

    @MainActor
    func testSchemaUpsertThenUndoRestoresPriorTypes() {
        let reg = freshSchema()
        let m = UndoManager()
        reg.undoManager = m

        let custom = ObjectType(
            id: "custom-\(UUID().uuidString)",
            name: "Custom", pluralName: "Customs",
            systemImage: "square", colorHex: "#000000",
            fields: [], builtIn: false,
            primaryFieldKey: nil, kanbanGroupKey: nil,
            calendarDateKey: nil, galleryAttachmentKey: nil,
            updatedAt: nil
        )
        let priorCount = reg.types.count
        reg.upsertType(custom)
        XCTAssertEqual(reg.types.count, priorCount + 1)

        XCTAssertTrue(m.canUndo)
        m.undo()
        XCTAssertEqual(reg.types.count, priorCount,
                       "undo of upsert should restore the prior types array")
        XCTAssertNil(reg.type(id: custom.id),
                     "undo should remove the just-added type")
    }

    @MainActor
    func testSchemaSetHiddenIsUndoable() {
        let reg = freshSchema()
        let m = UndoManager()
        reg.undoManager = m

        // Person is built-in and seeded
        let personId = "Person"
        XCTAssertNotNil(reg.type(id: personId))

        reg.setHidden(personId, hidden: true)
        XCTAssertFalse(reg.visibleTypes.contains { $0.id == personId },
                       "hidden built-in should drop out of visibleTypes")

        m.undo()
        XCTAssertTrue(reg.visibleTypes.contains { $0.id == personId },
                      "undo of setHidden should make the type visible again")
    }
}
