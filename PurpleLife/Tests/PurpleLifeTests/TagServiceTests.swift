import XCTest
import GRDB
@testable import PurpleLife

/// Increment 1 TagService tests. Run against the singleton
/// `DatabaseService.shared` and a fresh per-test `SettingsStore`
/// wired into `TagService.settings`. Each test wipes the `objects`,
/// `objects_fts`, and `record_tags` tables in setUp so state from
/// other tests in the bundle doesn't leak.
final class TagServiceTests: XCTestCase {

    @MainActor
    override func setUp() {
        super.setUp()
        let store = SettingsStore()
        store.settings.tagVocabulary = []
        store.save()
        TagService.settings = store

        let db = DatabaseService.shared
        try? db.dbPool.write { dbq in
            try dbq.execute(sql: "DELETE FROM record_tags")
            try dbq.execute(sql: "DELETE FROM objects_fts")
            try dbq.execute(sql: "DELETE FROM objects")
        }
        ObjectEngine.currentSchema = freshSchema()
    }

    @MainActor
    override func tearDown() {
        TagService.settings = nil
        super.tearDown()
    }

    @MainActor
    private func freshSchema() -> SchemaRegistry {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-tags-\(UUID().uuidString).json")
        return SchemaRegistry(fileURL: url)
    }

    // MARK: - Vocabulary

    @MainActor
    func testAddCreatesNewTag() {
        let tag = TagService.add(name: "urgent")
        XCTAssertNotNil(tag)
        XCTAssertEqual(TagService.allTags.count, 1)
        XCTAssertEqual(TagService.allTags.first?.name, "urgent")
    }

    @MainActor
    func testAddDedupesByNameCaseInsensitive() {
        let first  = TagService.add(name: "Urgent")
        let second = TagService.add(name: "urgent")
        XCTAssertEqual(first?.id, second?.id,
                       "Second add with same name (case-insensitive) returns the existing tag")
        XCTAssertEqual(TagService.allTags.count, 1)
    }

    @MainActor
    func testAddRejectsEmptyName() {
        XCTAssertNil(TagService.add(name: ""))
        XCTAssertNil(TagService.add(name: "   "))
        XCTAssertEqual(TagService.allTags.count, 0)
    }

    @MainActor
    func testRenameUpdatesNameAndTimestamp() {
        guard let tag = TagService.add(name: "old") else {
            return XCTFail("add returned nil")
        }
        let originalUpdatedAt = tag.updatedAt
        // Sleep a tiny amount so the ISO-8601 timestamp moves forward.
        Thread.sleep(forTimeInterval: 0.01)
        TagService.rename(id: tag.id, to: "new")
        let renamed = TagService.tag(id: tag.id)
        XCTAssertEqual(renamed?.name, "new")
        XCTAssertNotEqual(renamed?.updatedAt, originalUpdatedAt,
                          "rename should bump updatedAt for the forthcoming LWW sync")
    }

    @MainActor
    func testRenameRejectsCollidingName() {
        guard let alpha = TagService.add(name: "alpha") else { return XCTFail() }
        _ = TagService.add(name: "beta")
        TagService.rename(id: alpha.id, to: "beta")  // collides with the other tag
        XCTAssertEqual(TagService.tag(id: alpha.id)?.name, "alpha",
                       "Colliding rename must be a silent no-op")
    }

    @MainActor
    func testRecolorReplacesColor() {
        guard let tag = TagService.add(name: "blue", colorHex: "#0000FF") else { return XCTFail() }
        TagService.recolor(id: tag.id, colorHex: "#FF0000")
        XCTAssertEqual(TagService.tag(id: tag.id)?.colorHex, "#FF0000")
        TagService.recolor(id: tag.id, colorHex: nil)
        XCTAssertNil(TagService.tag(id: tag.id)?.colorHex)
    }

    // MARK: - Per-record

    @MainActor
    func testSetTagsPersistsToRecord() throws {
        let urgent = TagService.add(name: "urgent")!
        let later  = TagService.add(name: "later")!
        let rec = try ObjectEngine.create(typeId: "Person", fields: ["display_name": "Marie Curie"])
        let updated = try TagService.setTags([urgent.id, later.id], on: rec)
        XCTAssertEqual(Set(TagService.tagIds(on: updated)), Set([urgent.id, later.id]))
    }

    @MainActor
    func testSetTagsDedupes() throws {
        let urgent = TagService.add(name: "urgent")!
        let rec = try ObjectEngine.create(typeId: "Person", fields: ["display_name": "Curie"])
        let updated = try TagService.setTags([urgent.id, urgent.id, urgent.id], on: rec)
        XCTAssertEqual(TagService.tagIds(on: updated), [urgent.id])
    }

    @MainActor
    func testTagsOnResolvesAndDropsOrphans() throws {
        let urgent = TagService.add(name: "urgent")!
        let rec = try ObjectEngine.create(typeId: "Person", fields: ["display_name": "X"])
        let withUrgent = try TagService.setTags([urgent.id, "orphan-id-not-in-vocab"], on: rec)
        let resolved = TagService.tags(on: withUrgent)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.id, urgent.id)
    }

    // MARK: - `record_tags` index

    @MainActor
    func testIndexReflectsSetTags() throws {
        let urgent = TagService.add(name: "urgent")!
        let rec = try ObjectEngine.create(typeId: "Person", fields: ["display_name": "X"])
        _ = try TagService.setTags([urgent.id], on: rec)

        let rows = try DatabaseService.shared.dbPool.read { db in
            try Row.fetchAll(db, sql: "SELECT record_id, tag_id FROM record_tags")
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["record_id"] as String?, rec.id)
        XCTAssertEqual(rows.first?["tag_id"] as String?, urgent.id)
    }

    @MainActor
    func testIndexClearedOnRecordDelete() throws {
        let urgent = TagService.add(name: "urgent")!
        let rec = try ObjectEngine.create(typeId: "Person", fields: ["display_name": "X"])
        _ = try TagService.setTags([urgent.id], on: rec)
        try ObjectEngine.delete(id: rec.id)

        let count = try DatabaseService.shared.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM record_tags")
        } ?? -1
        XCTAssertEqual(count, 0, "Record delete must cascade to record_tags")
    }

    @MainActor
    func testReindexAllRebuildsFromFields() throws {
        let urgent = TagService.add(name: "urgent")!
        let rec = try ObjectEngine.create(typeId: "Person", fields: ["display_name": "X"])
        _ = try TagService.setTags([urgent.id], on: rec)

        // Simulate a missed write — wipe the index.
        try DatabaseService.shared.dbPool.write { db in
            try db.execute(sql: "DELETE FROM record_tags")
        }
        TagService.reindexAll()

        let count = try DatabaseService.shared.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM record_tags WHERE tag_id = ?",
                             arguments: [urgent.id])
        } ?? -1
        XCTAssertEqual(count, 1, "reindexAll must reinsert from each record's _tags")
    }

    // MARK: - Vocabulary-level fan-out

    @MainActor
    func testMergeRewritesRecords() throws {
        let alpha = TagService.add(name: "alpha")!
        let beta  = TagService.add(name: "beta")!
        let rec   = try ObjectEngine.create(typeId: "Person", fields: ["display_name": "X"])
        _ = try TagService.setTags([alpha.id], on: rec)

        TagService.merge(sourceId: alpha.id, into: beta.id)

        let after = try XCTUnwrap(try ObjectEngine.fetch(id: rec.id))
        XCTAssertEqual(TagService.tagIds(on: after), [beta.id],
                       "Merge should rewrite alpha -> beta on every record")
        XCTAssertNil(TagService.tag(id: alpha.id), "Source tag is removed from vocabulary")
        XCTAssertNotNil(TagService.tag(id: beta.id))

        let indexed = try DatabaseService.shared.dbPool.read { db in
            try String.fetchAll(db, sql: "SELECT tag_id FROM record_tags WHERE record_id = ?",
                                arguments: [rec.id])
        }
        XCTAssertEqual(indexed, [beta.id], "record_tags index reflects the rewrite")
    }

    @MainActor
    func testDeleteStripsFromRecords() throws {
        let urgent = TagService.add(name: "urgent")!
        let rec    = try ObjectEngine.create(typeId: "Person", fields: ["display_name": "X"])
        _ = try TagService.setTags([urgent.id], on: rec)

        TagService.delete(id: urgent.id)

        let after = try XCTUnwrap(try ObjectEngine.fetch(id: rec.id))
        XCTAssertEqual(TagService.tagIds(on: after), [],
                       "Deleting a tag strips it from every record")
        XCTAssertNil(TagService.tag(id: urgent.id))

        let indexed = try DatabaseService.shared.dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM record_tags WHERE record_id = ?",
                             arguments: [rec.id])
        } ?? -1
        XCTAssertEqual(indexed, 0, "record_tags index reflects the strip")
    }
}
