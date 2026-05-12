import XCTest
@testable import PurpleLife

/// The curated library + the materialize path that imports a copy into a
/// SchemaRegistry. Same coverage shape as ThemeIOTests / SchemaRegistryTests.
final class SchemaLibraryTests: XCTestCase {

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-\(UUID().uuidString).json")
    }

    // MARK: - Catalog shape

    func testCatalogIsNotEmpty() {
        XCTAssertGreaterThan(SchemaLibrary.entries.count, 20,
                             "The library is meant to showcase breadth — fewer than 20 entries hides that.")
    }

    func testEveryEntryHasUniqueId() {
        let ids = SchemaLibrary.entries.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count,
                       "duplicate library-entry ids would let entries shadow each other in search")
    }

    func testEveryEntryHasAPrimaryField() {
        for entry in SchemaLibrary.entries {
            guard let primary = entry.template.primaryFieldKey else {
                XCTFail("\(entry.id): no primaryFieldKey set; record screens would have no title")
                continue
            }
            XCTAssertNotNil(entry.template.fields.first { $0.key == primary },
                            "\(entry.id): primaryFieldKey '\(primary)' references a field that doesn't exist")
        }
    }

    func testEveryEntryHasAtLeastOneRequiredField() {
        for entry in SchemaLibrary.entries {
            XCTAssertTrue(entry.template.fields.contains { $0.required },
                          "\(entry.id): no required fields; the empty-state UX needs at least one anchor")
        }
    }

    func testKanbanGroupKeyAlwaysPointsAtSelectField() {
        for entry in SchemaLibrary.entries {
            guard let key = entry.template.kanbanGroupKey else { continue }
            let field = entry.template.fields.first { $0.key == key }
            XCTAssertNotNil(field, "\(entry.id): kanbanGroupKey '\(key)' missing")
            XCTAssertEqual(field?.kind, .select,
                           "\(entry.id): kanban group key must be a select field, got \(field?.kind.rawValue ?? "nil")")
        }
    }

    func testCalendarKeyAlwaysPointsAtDateField() {
        for entry in SchemaLibrary.entries {
            guard let key = entry.template.calendarDateKey else { continue }
            let field = entry.template.fields.first { $0.key == key }
            XCTAssertNotNil(field, "\(entry.id): calendarDateKey '\(key)' missing")
            XCTAssertTrue(field?.kind.canDateForCalendar ?? false,
                          "\(entry.id): calendar key must be a date/dateTime field")
        }
    }

    func testGalleryKeyAlwaysPointsAtAttachmentField() {
        for entry in SchemaLibrary.entries {
            guard let key = entry.template.galleryAttachmentKey else { continue }
            let field = entry.template.fields.first { $0.key == key }
            XCTAssertNotNil(field, "\(entry.id): galleryAttachmentKey '\(key)' missing")
            XCTAssertEqual(field?.kind, .attachment,
                           "\(entry.id): gallery key must be an attachment field")
        }
    }

    // MARK: - Search

    func testSearchByName() {
        let results = SchemaLibrary.search(query: "recipe")
        XCTAssertTrue(results.contains { $0.id == "lib.recipe" },
                      "'recipe' must match the Recipe template")
    }

    func testSearchByCategory() {
        let foodEntries = SchemaLibrary.search(query: "", category: .food)
        XCTAssertFalse(foodEntries.isEmpty)
        XCTAssertTrue(foodEntries.allSatisfy { $0.category == .food })
    }

    func testSearchByKeyword() {
        let results = SchemaLibrary.search(query: "norwegian")
        XCTAssertTrue(results.contains { $0.id == "lib.lefse" },
                      "keyword search should hit the lefse entry")
    }

    func testSearchIsCaseInsensitive() {
        let lower = SchemaLibrary.search(query: "vinyl")
        let upper = SchemaLibrary.search(query: "VINYL")
        XCTAssertEqual(lower.map(\.id), upper.map(\.id))
    }

    func testEmptyQueryReturnsAll() {
        let all = SchemaLibrary.search(query: "")
        XCTAssertEqual(all.count, SchemaLibrary.entries.count)
    }

    // MARK: - Materialize

    func testMaterializeProducesFreshIds() {
        guard let entry = SchemaLibrary.entry(id: "lib.recipe") else {
            XCTFail("recipe entry missing"); return
        }
        let a = entry.materialize()
        let b = entry.materialize()
        XCTAssertNotEqual(a.id, b.id, "two materializations must produce distinct type ids")
        let aFieldIds = Set(a.fields.map(\.id))
        let bFieldIds = Set(b.fields.map(\.id))
        XCTAssertTrue(aFieldIds.isDisjoint(with: bFieldIds),
                      "field ids must be regenerated per materialization")
    }

    func testMaterializeProducesUserDefinedType() {
        guard let entry = SchemaLibrary.entries.first else {
            XCTFail("library empty"); return
        }
        XCTAssertFalse(entry.materialize().builtIn,
                       "library entries must import as user-defined types, never built-ins")
    }

    func testMaterializePreservesFieldKeys() {
        guard let entry = SchemaLibrary.entry(id: "lib.recipe") else {
            XCTFail("recipe entry missing"); return
        }
        let original = entry.template.fields.map(\.key)
        let materialized = entry.materialize().fields.map(\.key)
        XCTAssertEqual(original, materialized,
                       "field keys must be stable across materialization — they're the record-data anchor")
    }

    // MARK: - Import into registry

    @MainActor
    func testImportingFromLibraryAddsAUserType() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)

        let initialCount = reg.types.count
        guard let entry = SchemaLibrary.entry(id: "lib.recipe") else {
            XCTFail("recipe entry missing"); return
        }
        let fresh = entry.materialize()
        reg.upsertType(fresh)

        XCTAssertEqual(reg.types.count, initialCount + 1)
        let inserted = try XCTUnwrap(reg.type(id: fresh.id))
        XCTAssertFalse(inserted.builtIn, "library entries always import as user-defined")
        XCTAssertEqual(inserted.name, "Recipe")
    }

    @MainActor
    func testRepeatedImportsDoNotCollide() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)

        guard let entry = SchemaLibrary.entry(id: "lib.recipe") else {
            XCTFail("recipe entry missing"); return
        }
        let first = entry.materialize()
        let second = entry.materialize()
        reg.upsertType(first)
        reg.upsertType(second)

        XCTAssertNotNil(reg.type(id: first.id))
        XCTAssertNotNil(reg.type(id: second.id))
        XCTAssertNotEqual(first.id, second.id,
                          "two imports of the same library entry must produce distinct registry types")
    }
}
