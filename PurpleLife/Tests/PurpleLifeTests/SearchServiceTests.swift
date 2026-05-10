import XCTest
import GRDB
@testable import PurpleLife

/// Phase 2 search layer — confirms FTS5 returns the right hits across
/// types and that the searchable-text projection picks up the fields the
/// user would expect to query.
///
/// Tests run against the singleton `DatabaseService.shared` because
/// `SearchService.search` reads from there. Each test cleans up after
/// itself (the FTS table is small and the test isolation is good
/// enough for now).
final class SearchServiceTests: XCTestCase {

    @MainActor
    private func freshSchema() -> SchemaRegistry {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-search-\(UUID().uuidString).json")
        return SchemaRegistry(fileURL: url)
    }

    @MainActor
    private func wipeAndSeed(schema: SchemaRegistry, fixtures: [(String, [String: Any])]) throws {
        // Wipe the singleton DB's relevant tables so the test starts clean.
        let db = DatabaseService.shared
        try db.dbPool.write { dbq in
            try dbq.execute(sql: "DELETE FROM objects_fts")
            try dbq.execute(sql: "DELETE FROM objects")
        }
        ObjectEngine.currentSchema = schema
        for (typeId, fields) in fixtures {
            _ = try ObjectEngine.create(typeId: typeId, fields: fields)
        }
    }

    @MainActor
    func testSearchAcrossTypes() throws {
        let schema = freshSchema()
        try wipeAndSeed(schema: schema, fixtures: [
            ("Person", ["display_name": "Ada Lovelace", "notes": "math pioneer"]),
            ("Person", ["display_name": "Grace Hopper", "notes": "compiler pioneer"]),
            ("Book",   ["title": "Numbers and the Making of Us", "author": "Caleb Everett"]),
            ("Camera", ["model": "Sony A7 IV", "brand": "Sony"]),
        ])

        let pioneers = SearchService.search("pioneer")
        XCTAssertEqual(pioneers.count, 2, "Both Person rows mention 'pioneer'")
        XCTAssertTrue(pioneers.allSatisfy { $0.typeId == "Person" })

        let sony = SearchService.search("sony")
        XCTAssertEqual(sony.first?.typeId, "Camera")
        XCTAssertEqual(sony.first?.title, "Sony A7 IV")

        let ada = SearchService.search("ada")
        XCTAssertTrue(ada.contains { $0.title == "Ada Lovelace" },
                      "Prefix match should surface Ada Lovelace")
    }

    @MainActor
    func testReindexRebuildsFromObjectsTable() throws {
        let schema = freshSchema()
        try wipeAndSeed(schema: schema, fixtures: [
            ("Person", ["display_name": "Linus Torvalds"])
        ])
        // Wipe the FTS table directly — simulates a missed write.
        try DatabaseService.shared.dbPool.write { dbq in
            try dbq.execute(sql: "DELETE FROM objects_fts")
        }
        XCTAssertTrue(SearchService.search("linus").isEmpty,
                      "FTS table emptied — search should return nothing")

        SearchService.reindexAll(schema: schema)
        XCTAssertFalse(SearchService.search("linus").isEmpty,
                       "Reindex should rebuild the FTS table from `objects`")
    }

    @MainActor
    func testEmptyQueryReturnsEmpty() throws {
        XCTAssertEqual(SearchService.search("").count, 0)
        XCTAssertEqual(SearchService.search("   ").count, 0)
    }

    @MainActor
    func testDeleteRemovesFromIndex() throws {
        let schema = freshSchema()
        try wipeAndSeed(schema: schema, fixtures: [
            ("Person", ["display_name": "Marie Curie"])
        ])
        XCTAssertEqual(SearchService.search("marie").count, 1)

        let all = try ObjectEngine.fetchAll()
        if let curie = all.first(where: { ($0.fields()["display_name"] as? String) == "Marie Curie" }) {
            try ObjectEngine.delete(id: curie.id)
        }
        XCTAssertEqual(SearchService.search("marie").count, 0,
                       "Delete should drop the FTS row")
    }
}
