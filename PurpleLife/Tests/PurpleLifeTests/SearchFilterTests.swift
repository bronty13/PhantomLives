import XCTest
import GRDB
@testable import PurpleLife

/// Tags Increment 3a — `SearchService.search(_ filter:)` tests.
/// Exercises every dimension of `Filter` (free text, type scope,
/// excludingTypeIds for Vault gating, tag IN .any / .all, untagged,
/// date range, limit) and confirms they compose correctly.
final class SearchFilterTests: XCTestCase {

    @MainActor
    private func freshSchema() -> SchemaRegistry {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-filter-\(UUID().uuidString).json")
        return SchemaRegistry(fileURL: url)
    }

    @MainActor
    private func wipeAndSeed(schema: SchemaRegistry,
                             fixtures: [(typeId: String, fields: [String: Any])])
        throws -> [ObjectRecord]
    {
        let db = DatabaseService.shared
        try db.dbPool.write { dbq in
            try dbq.execute(sql: "DELETE FROM record_tags")
            try dbq.execute(sql: "DELETE FROM objects_fts")
            try dbq.execute(sql: "DELETE FROM objects")
        }
        ObjectEngine.currentSchema = schema
        var out: [ObjectRecord] = []
        for fixture in fixtures {
            out.append(try ObjectEngine.create(typeId: fixture.typeId, fields: fixture.fields))
        }
        return out
    }

    @MainActor
    private func setUpTagService() -> SettingsStore {
        let store = SettingsStore()
        store.settings.tagVocabulary = []
        store.save()
        TagService.settings = store
        return store
    }

    // MARK: - Free-text and structural baseline

    @MainActor
    func test_emptyFilterReturnsEverythingNewestFirst() throws {
        _ = setUpTagService()
        let schema = freshSchema()
        let recs = try wipeAndSeed(schema: schema, fixtures: [
            ("Person", ["display_name": "First"]),
            ("Book",   ["title":        "Second"]),
            ("Camera", ["model":        "Third"])
        ])
        // Stamp distinct updated_at values so the DESC ordering is
        // unambiguous (default ISO-8601 strings collide at second
        // precision when inserts happen in the same instant).
        let f = ISO8601DateFormatter()
        try DatabaseService.shared.dbPool.write { db in
            try db.execute(sql: "UPDATE objects SET updated_at = ? WHERE id = ?",
                           arguments: [f.string(from: Date(timeIntervalSinceNow: -30)), recs[0].id])
            try db.execute(sql: "UPDATE objects SET updated_at = ? WHERE id = ?",
                           arguments: [f.string(from: Date(timeIntervalSinceNow: -20)), recs[1].id])
            try db.execute(sql: "UPDATE objects SET updated_at = ? WHERE id = ?",
                           arguments: [f.string(from: Date(timeIntervalSinceNow: -10)), recs[2].id])
        }
        let hits = SearchService.search(.init())
        XCTAssertEqual(hits.count, 3)
        XCTAssertEqual(hits.map(\.recordId), [recs[2].id, recs[1].id, recs[0].id],
                       "Newest updated_at first, in stamped order")
    }

    @MainActor
    func test_filterByQueryRunsTheSameAsFreeTextOverload() throws {
        _ = setUpTagService()
        let schema = freshSchema()
        _ = try wipeAndSeed(schema: schema, fixtures: [
            ("Person", ["display_name": "Ada Lovelace"]),
            ("Person", ["display_name": "Grace Hopper"])
        ])
        var filter = SearchService.Filter()
        filter.query = "ada"
        let hits = SearchService.search(filter)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.title, "Ada Lovelace")
    }

    @MainActor
    func test_filterByTypeIdsRestrictsResults() throws {
        _ = setUpTagService()
        let schema = freshSchema()
        _ = try wipeAndSeed(schema: schema, fixtures: [
            ("Person", ["display_name": "Curie"]),
            ("Book",   ["title":        "Curie biography"])
        ])
        var filter = SearchService.Filter()
        filter.query = "curie"
        filter.typeIds = ["Book"]
        let hits = SearchService.search(filter)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.typeId, "Book")
    }

    @MainActor
    func test_excludingTypeIdsAppliesEvenWhenTypeIdsIncludesIt() throws {
        // Vault gating contract: even if the user has the type
        // selected via the chip picker, excludingTypeIds wins.
        // (Practically the UI won't surface Vault chips when locked,
        // but the SQL must enforce the invariant regardless.)
        _ = setUpTagService()
        let schema = freshSchema()
        _ = try wipeAndSeed(schema: schema, fixtures: [
            ("Person", ["display_name": "Visible"]),
            ("Book",   ["title":        "AlsoMatch"])
        ])
        var filter = SearchService.Filter()
        filter.typeIds = ["Person", "Book"]
        filter.excludingTypeIds = ["Book"]
        let hits = SearchService.search(filter)
        XCTAssertEqual(hits.map(\.typeId), ["Person"])
    }

    // MARK: - Tag filtering

    @MainActor
    func test_requiredTagIdsAnyModeReturnsRecordsWithAnyMatchingTag() throws {
        let _ = setUpTagService()
        let schema = freshSchema()
        let recs = try wipeAndSeed(schema: schema, fixtures: [
            ("Person", ["display_name": "A"]),
            ("Person", ["display_name": "B"]),
            ("Person", ["display_name": "C"])
        ])
        let urgent = try XCTUnwrap(TagService.add(name: "urgent"))
        let later  = try XCTUnwrap(TagService.add(name: "later"))
        _ = try TagService.setTags([urgent.id], on: recs[0])
        _ = try TagService.setTags([later.id],  on: recs[1])
        // recs[2] has no tags

        var filter = SearchService.Filter()
        filter.requiredTagIds = [urgent.id, later.id]
        filter.tagMatchMode = .any
        let hits = SearchService.search(filter)
        XCTAssertEqual(Set(hits.map(\.title)), ["A", "B"])
    }

    @MainActor
    func test_requiredTagIdsAllModeRequiresEveryTag() throws {
        let _ = setUpTagService()
        let schema = freshSchema()
        let recs = try wipeAndSeed(schema: schema, fixtures: [
            ("Person", ["display_name": "BothTags"]),
            ("Person", ["display_name": "OneTag"])
        ])
        let urgent = try XCTUnwrap(TagService.add(name: "urgent"))
        let later  = try XCTUnwrap(TagService.add(name: "later"))
        _ = try TagService.setTags([urgent.id, later.id], on: recs[0])
        _ = try TagService.setTags([urgent.id],            on: recs[1])

        var filter = SearchService.Filter()
        filter.requiredTagIds = [urgent.id, later.id]
        filter.tagMatchMode = .all
        let hits = SearchService.search(filter)
        XCTAssertEqual(hits.map(\.title), ["BothTags"])
    }

    @MainActor
    func test_untaggedOnlyExcludesEveryTaggedRecord() throws {
        let _ = setUpTagService()
        let schema = freshSchema()
        let recs = try wipeAndSeed(schema: schema, fixtures: [
            ("Person", ["display_name": "Tagged"]),
            ("Person", ["display_name": "Bare"])
        ])
        let tag = try XCTUnwrap(TagService.add(name: "anything"))
        _ = try TagService.setTags([tag.id], on: recs[0])

        var filter = SearchService.Filter()
        filter.untaggedOnly = true
        let hits = SearchService.search(filter)
        XCTAssertEqual(hits.map(\.title), ["Bare"])
    }

    @MainActor
    func test_requiredTagIdsTakesPrecedenceOverUntaggedOnly() throws {
        // Defined behavior: when both are set, the more specific
        // requiredTagIds wins. The UI never lets the user select
        // both, but the SQL composer must not crash if they do.
        let _ = setUpTagService()
        let schema = freshSchema()
        let recs = try wipeAndSeed(schema: schema, fixtures: [
            ("Person", ["display_name": "Tagged"])
        ])
        let tag = try XCTUnwrap(TagService.add(name: "anything"))
        _ = try TagService.setTags([tag.id], on: recs[0])

        var filter = SearchService.Filter()
        filter.requiredTagIds = [tag.id]
        filter.untaggedOnly = true   // should be ignored
        let hits = SearchService.search(filter)
        XCTAssertEqual(hits.map(\.title), ["Tagged"])
    }

    // MARK: - Date range

    @MainActor
    func test_dateRangeOnlyReturnsRecordsWithinBounds() throws {
        _ = setUpTagService()
        let schema = freshSchema()
        // Create three records, then hand-edit their updated_at so
        // we can reason about which falls inside the range.
        let recs = try wipeAndSeed(schema: schema, fixtures: [
            ("Person", ["display_name": "Old"]),
            ("Person", ["display_name": "Middle"]),
            ("Person", ["display_name": "Recent"])
        ])
        let f = ISO8601DateFormatter()
        try DatabaseService.shared.dbPool.write { db in
            try db.execute(sql: "UPDATE objects SET updated_at = ? WHERE id = ?",
                           arguments: [f.string(from: Date(timeIntervalSinceNow: -10 * 86400)), recs[0].id])
            try db.execute(sql: "UPDATE objects SET updated_at = ? WHERE id = ?",
                           arguments: [f.string(from: Date(timeIntervalSinceNow: -3 * 86400)),  recs[1].id])
            try db.execute(sql: "UPDATE objects SET updated_at = ? WHERE id = ?",
                           arguments: [f.string(from: Date()),                                   recs[2].id])
        }

        var filter = SearchService.Filter()
        filter.dateRange = .init(
            from: Date(timeIntervalSinceNow: -5 * 86400),
            to:   Date()
        )
        let hits = SearchService.search(filter)
        XCTAssertEqual(Set(hits.map(\.title)), ["Middle", "Recent"])
    }

    // MARK: - Composition

    @MainActor
    func test_queryAndTypeAndTagAllCompose() throws {
        _ = setUpTagService()
        let schema = freshSchema()
        let recs = try wipeAndSeed(schema: schema, fixtures: [
            ("Person", ["display_name": "Ada Lovelace"]),
            ("Person", ["display_name": "Ada Wong"]),
            ("Book",   ["title":        "Ada the Programmer"])
        ])
        let tag = try XCTUnwrap(TagService.add(name: "tech"))
        _ = try TagService.setTags([tag.id], on: recs[0]) // Lovelace tagged
        // recs[1] Wong: not tagged
        // recs[2] Book: not in scope

        var filter = SearchService.Filter()
        filter.query = "ada"
        filter.typeIds = ["Person"]
        filter.requiredTagIds = [tag.id]
        let hits = SearchService.search(filter)
        XCTAssertEqual(hits.map(\.title), ["Ada Lovelace"])
    }

    @MainActor
    func test_limitIsHonoredAgainstFilteredSet() throws {
        _ = setUpTagService()
        let schema = freshSchema()
        for i in 0..<10 {
            _ = try ObjectEngine.create(typeId: "Person", fields: ["display_name": "P\(i)"])
        }
        var filter = SearchService.Filter()
        filter.limit = 3
        let hits = SearchService.search(filter)
        XCTAssertEqual(hits.count, 3)
    }
}
