import XCTest
import GRDB
@testable import PurpleLife

/// Phase 1 unit coverage for the storage shape — make sure the JSON-blob
/// column round-trips and the indexes back the queries the engine hits.
/// `ObjectEngine` itself is a thin facade over the singleton DB; these
/// tests drive the migrator directly against an in-memory queue so they
/// never touch the developer's real ~/Library/Application Support state.
final class ObjectEngineTests: XCTestCase {

    private func makeMigratedQueue() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try DatabaseService.applyMigrations(to: queue)
        return queue
    }

    func testFieldsJSONRoundtrip() throws {
        let queue = try makeMigratedQueue()
        let now = ISO8601DateFormatter().string(from: Date())
        let original = ObjectRecord(
            id: "abc",
            typeId: "Person",
            parentId: nil,
            fieldsJSON: #"{"displayName":"Ada","tags":["a","b"]}"#,
            createdAt: now,
            updatedAt: now
        )
        try queue.write { db in try original.insert(db) }

        let fetched = try queue.read { db in
            try ObjectRecord.fetchOne(db, key: "abc")
        }
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.fieldsJSON, original.fieldsJSON)
        XCTAssertEqual(fetched?.fields()["displayName"] as? String, "Ada")
    }

    func testFilterByType() throws {
        let queue = try makeMigratedQueue()
        let now = ISO8601DateFormatter().string(from: Date())
        try queue.write { db in
            for i in 0..<5 {
                try ObjectRecord(
                    id: "p-\(i)", typeId: "Person", parentId: nil,
                    fieldsJSON: "{}", createdAt: now, updatedAt: now
                ).insert(db)
            }
            for i in 0..<3 {
                try ObjectRecord(
                    id: "b-\(i)", typeId: "Book", parentId: nil,
                    fieldsJSON: "{}", createdAt: now, updatedAt: now
                ).insert(db)
            }
        }

        let people = try queue.read { db in
            try ObjectRecord.filter(Column("type_id") == "Person").fetchAll(db)
        }
        let books = try queue.read { db in
            try ObjectRecord.filter(Column("type_id") == "Book").fetchAll(db)
        }
        XCTAssertEqual(people.count, 5)
        XCTAssertEqual(books.count, 3)
    }

    func testParentChildRelation() throws {
        let queue = try makeMigratedQueue()
        let now = ISO8601DateFormatter().string(from: Date())
        let parent = ObjectRecord(
            id: "parent", typeId: "PhotoShoot", parentId: nil,
            fieldsJSON: "{}", createdAt: now, updatedAt: now
        )
        let child1 = ObjectRecord(
            id: "child-1", typeId: "Photo", parentId: "parent",
            fieldsJSON: "{}", createdAt: now, updatedAt: now
        )
        let child2 = ObjectRecord(
            id: "child-2", typeId: "Photo", parentId: "parent",
            fieldsJSON: "{}", createdAt: now, updatedAt: now
        )
        try queue.write { db in
            try parent.insert(db)
            try child1.insert(db)
            try child2.insert(db)
        }

        let children = try queue.read { db in
            try ObjectRecord
                .filter(Column("parent_id") == "parent")
                .fetchAll(db)
        }
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(Set(children.map(\.id)), Set(["child-1", "child-2"]))
    }
}
