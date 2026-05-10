import XCTest
import GRDB
@testable import PurpleLife

/// Phase 3 QueryRunner — exercises filter / sort / limit semantics
/// against the singleton DB, isolated by wiping `objects` + `objects_fts`
/// before each test.
final class QueryRunnerTests: XCTestCase {

    @MainActor
    private func freshSchemaAndWipe() throws -> SchemaRegistry {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-query-\(UUID().uuidString).json")
        let schema = SchemaRegistry(fileURL: url)
        ObjectEngine.currentSchema = schema
        try DatabaseService.shared.dbPool.write { db in
            try db.execute(sql: "DELETE FROM objects_fts")
            try db.execute(sql: "DELETE FROM objects")
        }
        return schema
    }

    @MainActor
    func testTypeFilterAndLimit() throws {
        let schema = try freshSchemaAndWipe()
        for i in 0..<3 {
            _ = try ObjectEngine.create(typeId: "Person", fields: ["display_name": "Person \(i)"])
        }
        for i in 0..<2 {
            _ = try ObjectEngine.create(typeId: "Book", fields: ["title": "Book \(i)"])
        }

        let q = SavedQuery.make(name: "People", systemImage: "person", typeId: "Person", limit: 2)
        let results = QueryRunner.run(q, schema: schema)
        XCTAssertEqual(results.count, 2, "Limit should clamp to 2")
        XCTAssertTrue(results.allSatisfy { $0.type.id == "Person" })
    }

    @MainActor
    func testFieldEqualsFilter() throws {
        let schema = try freshSchemaAndWipe()
        _ = try ObjectEngine.create(typeId: "Book", fields: ["title": "A", "status": "Reading"])
        _ = try ObjectEngine.create(typeId: "Book", fields: ["title": "B", "status": "Finished"])
        _ = try ObjectEngine.create(typeId: "Book", fields: ["title": "C", "status": "Reading"])

        let q = SavedQuery.make(
            name: "Reading",
            systemImage: "book",
            typeId: "Book",
            filterFieldKey: "status",
            filterValue: .string("Reading"),
            limit: 10
        )
        let results = QueryRunner.run(q, schema: schema)
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { ($0.record.fields()["status"] as? String) == "Reading" })
    }

    @MainActor
    func testWithinDaysFiltersByUpdatedAt() throws {
        let schema = try freshSchemaAndWipe()
        // Two recent rows + one ancient row (we backdate by writing
        // updated_at directly).
        let now = ISO8601DateFormatter().string(from: Date())
        let ancient = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-30 * 86400))
        try DatabaseService.shared.dbPool.write { db in
            for (id, ts) in [("a", now), ("b", now), ("c", ancient)] {
                try db.execute(
                    sql: """
                        INSERT INTO objects (id, type_id, parent_id, fields_json, created_at, updated_at)
                        VALUES (?, ?, NULL, '{}', ?, ?)
                    """,
                    arguments: [id, "Person", ts, ts]
                )
            }
        }
        SearchService.reindexAll(schema: schema)

        let q = SavedQuery.make(
            name: "This week",
            systemImage: "sparkles",
            filterValue: .withinDays(7),
            limit: 50
        )
        let results = QueryRunner.run(q, schema: schema)
        XCTAssertEqual(results.count, 2)
        XCTAssertFalse(results.contains { $0.record.id == "c" }, "30-day-old row must be excluded")
    }

    @MainActor
    func testSortByFieldDescendingAndAscending() throws {
        let schema = try freshSchemaAndWipe()
        _ = try ObjectEngine.create(typeId: "Book", fields: ["title": "Banana"])
        _ = try ObjectEngine.create(typeId: "Book", fields: ["title": "Apple"])
        _ = try ObjectEngine.create(typeId: "Book", fields: ["title": "Cherry"])

        let asc = SavedQuery.make(
            name: "A→Z", systemImage: "book", typeId: "Book",
            sortFieldKey: "title", descending: false, limit: 10
        )
        let ascResults = QueryRunner.run(asc, schema: schema)
        XCTAssertEqual(ascResults.map { $0.record.fields()["title"] as? String }, ["Apple", "Banana", "Cherry"])

        let desc = SavedQuery.make(
            name: "Z→A", systemImage: "book", typeId: "Book",
            sortFieldKey: "title", descending: true, limit: 10
        )
        let descResults = QueryRunner.run(desc, schema: schema)
        XCTAssertEqual(descResults.map { $0.record.fields()["title"] as? String }, ["Cherry", "Banana", "Apple"])
    }

    @MainActor
    func testCrossTypeQueryReturnsEverything() throws {
        let schema = try freshSchemaAndWipe()
        _ = try ObjectEngine.create(typeId: "Person", fields: ["display_name": "Ada"])
        _ = try ObjectEngine.create(typeId: "Book",   fields: ["title": "Vintage"])
        _ = try ObjectEngine.create(typeId: "Camera", fields: ["model": "Sony A7 IV"])

        let q = SavedQuery.make(name: "All", systemImage: "sparkles", typeId: nil, limit: 50)
        let results = QueryRunner.run(q, schema: schema)
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(Set(results.map { $0.type.id }), Set(["Person", "Book", "Camera"]))
    }
}
