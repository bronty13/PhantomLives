import XCTest
@testable import PurpleLife

/// JSON envelope import/export for `ObjectType`. UI is unit-tested
/// separately — this covers encode/decode/fresh-id behavior.
final class SchemaIOTests: XCTestCase {

    private func sampleType(id: String = "Sample", name: String = "Sample") -> ObjectType {
        ObjectType(
            id: id,
            name: name,
            pluralName: "\(name)s",
            systemImage: "square",
            colorHex: "#9D4DCC",
            fields: [
                FieldDef.make(name: "Title", kind: .text, required: true),
                FieldDef.make(name: "Notes", kind: .longText),
            ],
            builtIn: false,
            primaryFieldKey: "title",
            kanbanGroupKey: nil,
            calendarDateKey: nil,
            galleryAttachmentKey: nil
        )
    }

    // MARK: - Filename sanitization

    func testSanitizedFilenameStripsPathSeparators() {
        XCTAssertEqual(SchemaIO.sanitizedFilename("My / Schemas"), "My  Schemas")
        XCTAssertEqual(SchemaIO.sanitizedFilename(".."), "schema",
                       "all-dots collapses to a fallback rather than producing a hidden file")
    }

    func testDefaultFilenameUsesPluralName() {
        let t = sampleType(name: "Recipe")
        XCTAssertEqual(SchemaIO.defaultFilename(for: t), "Recipes.purplelifeschema.json")
    }

    func testBundleFilename() {
        let one = sampleType(name: "Recipe")
        let two = sampleType(id: "Two", name: "Book")
        XCTAssertEqual(SchemaIO.defaultFilenameForBundle([one]), "Recipes.purplelifeschema.json")
        XCTAssertEqual(SchemaIO.defaultFilenameForBundle([one, two]), "schemas-2.purplelifeschema.json")
    }

    // MARK: - Encode / decode roundtrip

    func testEncodeProducesPrettySortedJSON() throws {
        let data = try SchemaIO.encode([sampleType()])
        let s = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("\n"))
        XCTAssertTrue(s.contains("\"format\""))
        XCTAssertTrue(s.contains("\"purplelife.schema.v1\""))
    }

    func testDecodeRoundtripAssignsFreshIds() throws {
        let original = sampleType()
        let data = try SchemaIO.encode([original])
        let imported = try SchemaIO.decode(from: data)

        XCTAssertEqual(imported.count, 1)
        let one = imported[0]
        XCTAssertEqual(one.name, original.name, "name preserved")
        XCTAssertNotEqual(one.id, original.id, "type id must be regenerated on import")
        let importedFieldIds = Set(one.fields.map(\.id))
        let originalFieldIds = Set(original.fields.map(\.id))
        XCTAssertTrue(importedFieldIds.isDisjoint(with: originalFieldIds),
                      "field ids must be regenerated on import")
        XCTAssertEqual(one.fields.map(\.key), original.fields.map(\.key),
                       "field keys must survive (records key by key, not by id)")
    }

    func testDecodeForcesUserDefined() throws {
        var seed = sampleType()
        seed.builtIn = true     // even if someone hand-crafts builtIn=true...
        let data = try SchemaIO.encode([seed])
        let imported = try SchemaIO.decode(from: data)
        XCTAssertFalse(imported[0].builtIn,
                       "imports never claim built-in status — that's reserved for ids the app ships with")
    }

    func testMultipleTypesRoundtrip() throws {
        let a = sampleType(id: "A", name: "Alpha")
        let b = sampleType(id: "B", name: "Beta")
        let data = try SchemaIO.encode([a, b])
        let imported = try SchemaIO.decode(from: data)
        XCTAssertEqual(imported.map(\.name).sorted(), ["Alpha", "Beta"])
    }

    func testWriteAndReadRoundtripsThroughDisk() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-\(UUID().uuidString).purplelifeschema.json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let one = sampleType(name: "Hike")
        try SchemaIO.write([one], to: tmp)
        let read = try SchemaIO.read(from: tmp)
        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read[0].name, "Hike")
        XCTAssertNotEqual(read[0].id, one.id, "fresh id on disk-read")
    }

    // MARK: - Failure modes

    func testDecodeRejectsCorruptJSON() {
        let bad = Data("not-json-at-all".utf8)
        XCTAssertThrowsError(try SchemaIO.decode(from: bad))
    }

    func testDecodeRejectsWrongFormatTag() {
        let json = #"{"format":"somethingelse","exportedAt":"2026-01-01T00:00:00Z","types":[]}"#
        XCTAssertThrowsError(try SchemaIO.decode(from: Data(json.utf8))) { err in
            if case SchemaIO.ImportError.unrecognizedFormat = err { return }
            XCTFail("expected ImportError.unrecognizedFormat, got \(err)")
        }
    }

    func testDecodeRejectsEmptyEnvelope() {
        let json = #"{"format":"purplelife.schema.v1","exportedAt":"2026-01-01T00:00:00Z","types":[]}"#
        XCTAssertThrowsError(try SchemaIO.decode(from: Data(json.utf8))) { err in
            if case SchemaIO.ImportError.empty = err { return }
            XCTFail("expected ImportError.empty, got \(err)")
        }
    }

    func testDecodeAcceptsBareArrayAsForwardCompat() throws {
        // Hand-rolled file: just an array of ObjectType, no envelope.
        let encoder = JSONEncoder()
        let data = try encoder.encode([sampleType(name: "Stripped")])
        let imported = try SchemaIO.decode(from: data)
        XCTAssertEqual(imported.first?.name, "Stripped")
    }
}

// MARK: - SchemaRegistry import / reset

/// Tests for the multi-type import + reset-to-defaults paths added on
/// SchemaRegistry alongside the gallery feature.
final class SchemaRegistryImportTests: XCTestCase {

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-\(UUID().uuidString).json")
    }

    @MainActor
    func testImportTypesAddsThemAsUserDefined() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)

        let initial = reg.types.count
        let imported = ObjectType(
            id: "ignored",
            name: "Imported",
            pluralName: "Imported",
            systemImage: "tray",
            colorHex: "#9D4DCC",
            fields: [FieldDef.make(name: "Title", kind: .text, required: true)],
            builtIn: true,    // even a hand-crafted builtIn=true gets stripped
            primaryFieldKey: "title",
            kanbanGroupKey: nil,
            calendarDateKey: nil,
            galleryAttachmentKey: nil
        )
        let ids = reg.importTypes([imported])
        XCTAssertEqual(ids.count, 1)
        XCTAssertEqual(reg.types.count, initial + 1)
        let stored = try XCTUnwrap(reg.type(id: ids[0]))
        XCTAssertFalse(stored.builtIn, "imports never become built-ins")
    }

    @MainActor
    func testImportTypesRenamesCollidingPluralNames() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)

        // Books is a built-in plural.
        let dup = ObjectType(
            id: "ignored",
            name: "Book", pluralName: "Books",
            systemImage: "book", colorHex: "#9D4DCC",
            fields: [FieldDef.make(name: "Title", kind: .text, required: true)],
            builtIn: false,
            primaryFieldKey: "title",
            kanbanGroupKey: nil, calendarDateKey: nil, galleryAttachmentKey: nil
        )
        let ids = reg.importTypes([dup])
        let stored = try XCTUnwrap(reg.type(id: ids[0]))
        XCTAssertEqual(stored.pluralName, "Books (imported)",
                       "colliding plural name must be suffixed so the sidebar isn't visually duplicate")
    }

    @MainActor
    func testResetBuiltInsRestoresSchemaSeed() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)

        // Mutate a built-in: rename, drop a field.
        var person = try XCTUnwrap(reg.type(id: "Person"))
        person.pluralName = "Mutants"
        person.fields = []
        reg.upsertType(person)
        XCTAssertEqual(reg.type(id: "Person")?.pluralName, "Mutants")
        XCTAssertEqual(reg.type(id: "Person")?.fields.count, 0)

        reg.resetBuiltInsToDefaults()

        let restored = try XCTUnwrap(reg.type(id: "Person"))
        XCTAssertEqual(restored.pluralName, "People")
        XCTAssertFalse(restored.fields.isEmpty,
                       "reset must restore the seed's field list")
    }

    @MainActor
    func testResetBuiltInsPreservesUserDefinedTypes() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let reg = SchemaRegistry(fileURL: url)

        let custom = ObjectType(
            id: "MyRecipe",
            name: "My Recipe", pluralName: "My Recipes",
            systemImage: "fork.knife", colorHex: "#E8A93B",
            fields: [FieldDef.make(name: "Title", kind: .text, required: true)],
            builtIn: false,
            primaryFieldKey: "title",
            kanbanGroupKey: nil, calendarDateKey: nil, galleryAttachmentKey: nil
        )
        reg.upsertType(custom)
        XCTAssertNotNil(reg.type(id: "MyRecipe"))

        reg.resetBuiltInsToDefaults()
        XCTAssertNotNil(reg.type(id: "MyRecipe"),
                        "reset must NOT touch user-defined types")
    }
}
