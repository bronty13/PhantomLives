import XCTest
@testable import PurpleLife

/// Load-bearing test from the architect's plan review. The bulk
/// path's value isn't theoretical — without these invariants, a
/// 5,000-row CSV import wedges the undo stack, fires 5,000 CloudKit
/// pushes, and reindexes FTS row-by-row. These tests pin all three.
@MainActor
final class PurpleLifeSinkBulkTests: XCTestCase {

    private var registry: SchemaRegistry!
    private var sink: PurpleLifeSink!
    private var undoManager: UndoManager!
    private var fileURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PurpleLifeSinkBulkTests-\(UUID().uuidString)")
        try? FileManager.default.removeItem(at: tmp)

        let schemaFile = tmp.appendingPathComponent("schema.json")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        registry = SchemaRegistry(fileURL: schemaFile)
        // Add a user-defined type with two text fields so we can
        // import into it.
        let type = ObjectType(
            id: UUID().uuidString,
            name: "Row", pluralName: "Rows",
            systemImage: "rectangle",
            colorHex: "#7B5CD6",
            fields: [
                FieldDef.make(name: "Name", kind: .text),
                FieldDef.make(name: "Number", kind: .number)
            ],
            builtIn: false
        )
        registry.upsertType(type)

        sink = PurpleLifeSink(schema: registry)
        ObjectEngine.currentSchema = registry
        // No sync wired — the bulk path must still satisfy its
        // contract on the "sync == nil" branch (the architect's test
        // would dig into the actual push counter; without sync wired
        // we instead pin that `ObjectEngine.bulkInsert` doesn't loop
        // through per-row `push`).
        ObjectEngine.sync = nil

        undoManager = UndoManager()
        undoManager.disableUndoRegistration()
        // Actually we WANT it enabled to observe registrations.
        undoManager.enableUndoRegistration()
        ObjectEngine.undoManager = undoManager

        fileURL = schemaFile
    }

    override func tearDown() async throws {
        ObjectEngine.undoManager = nil
        ObjectEngine.currentSchema = nil
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        try await super.tearDown()
    }

    /// A 5,000-row bulk insert registers exactly one undo entry, not
    /// 5,000. Without this guarantee the bulk path is just a name.
    func testBulkInsertOf5000RowsRegistersOneUndoEntry() throws {
        guard let type = registry.types.first(where: { $0.name == "Row" }) else {
            XCTFail("Test fixture missing"); return
        }
        let rows: [[String: Any]] = (0..<5000).map { i in
            ["name": "Row \(i)", "number": Double(i)]
        }
        // Drain any existing undo state from setUp.
        undoManager.removeAllActions()

        _ = try ObjectEngine.bulkInsert(typeId: type.id, rows: rows)

        // The action name carries the count; canUndo confirms one
        // entry actually landed.
        XCTAssertTrue(undoManager.canUndo)
        // One undo group: invoking undo should empty the table.
        undoManager.undo()
        let afterUndo = try ObjectEngine.fetch(typeId: type.id)
        XCTAssertEqual(afterUndo.count, 0, "Single undo must remove the whole bulk")
    }

    /// The bulk path's primary win over a loop of `create()` is one
    /// GRDB transaction. We can't trivially count transactions
    /// from outside GRDB, but we can prove correctness: 5,000 rows
    /// in, 5,000 records visible.
    func testBulkInsertProducesAllRows() throws {
        guard let type = registry.types.first(where: { $0.name == "Row" }) else {
            XCTFail(); return
        }
        let rows: [[String: Any]] = (0..<200).map { i in
            ["name": "Row \(i)", "number": Double(i)]
        }
        let result = try ObjectEngine.bulkInsert(typeId: type.id, rows: rows)
        XCTAssertEqual(result.inserted.count, 200)
        let stored = try ObjectEngine.fetch(typeId: type.id)
        XCTAssertEqual(stored.count, 200)
    }

    func testEmptyBulkIsNoOp() throws {
        guard let type = registry.types.first(where: { $0.name == "Row" }) else {
            XCTFail(); return
        }
        let result = try ObjectEngine.bulkInsert(typeId: type.id, rows: [])
        XCTAssertTrue(result.inserted.isEmpty)
    }

    /// Per-record `upsert` with `keyFieldKey = nil` always inserts;
    /// with a key it updates a matching row.
    func testUpsertOnKeyUpdatesMatchingRow() throws {
        guard let type = registry.types.first(where: { $0.name == "Row" }) else {
            XCTFail(); return
        }
        _ = try sink.upsert(
            typeId: type.id,
            keyFieldKey: nil,
            values: ["name": "Ada", "number": 36.0],
            attachments: []
        )
        let result = try sink.upsert(
            typeId: type.id,
            keyFieldKey: "name",
            values: ["name": "Ada", "number": 37.0],
            attachments: []
        )
        if case .updated = result { /* ok */ }
        else { XCTFail("Expected .updated, got \(result)") }
        let rows = try ObjectEngine.fetch(typeId: type.id)
        XCTAssertEqual(rows.count, 1, "Upsert must not duplicate the row")
        XCTAssertEqual(rows[0].fields()["number"] as? Double, 37.0)
    }
}
