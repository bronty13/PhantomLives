import XCTest
@testable import PurpleLife

@MainActor
final class MappingStoreTests: XCTestCase {

    private func makeStore() -> (MappingStore, URL) {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MappingStoreTests-\(UUID().uuidString)", isDirectory: true)
        let store = MappingStore(directoryURL: tmp, keyResolver: { nil })
        return (store, tmp)
    }

    func testSaveAndReload() throws {
        let (store, tmp) = makeStore()
        defer { try? FileManager.default.removeItem(at: tmp) }

        var draft = SavedImportMapping.newDraft()
        draft.name = "Test mapping"
        let saved = try store.save(draft)

        let restored = MappingStore(directoryURL: tmp, keyResolver: { nil })
        XCTAssertEqual(restored.mappings.count, 1)
        XCTAssertEqual(restored.mappings.first?.id, saved.id)
        XCTAssertEqual(restored.mappings.first?.name, "Test mapping")
    }

    func testMalformedFileDoesNotPoisonOtherEntries() throws {
        // Plan design decision #7 promised this. Verify.
        let (store, tmp) = makeStore()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Save a good mapping…
        var good = SavedImportMapping.newDraft()
        good.name = "Good"
        _ = try store.save(good)

        // …then plant a malformed file next to it.
        let bad = tmp.appendingPathComponent("garbage.purplelifemapping.json")
        try "this is not json".write(to: bad, atomically: true, encoding: .utf8)

        let restored = MappingStore(directoryURL: tmp, keyResolver: { nil })
        XCTAssertEqual(restored.mappings.count, 1, "Bad file must not break loading the good one")
        XCTAssertEqual(restored.mappings.first?.name, "Good")
    }

    func testDelete() throws {
        let (store, tmp) = makeStore()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let saved = try store.save(SavedImportMapping.newDraft())
        let path = store.fileURL(for: saved.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        store.delete(id: saved.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
        XCTAssertTrue(store.mappings.isEmpty)
    }

    func testDuplicate() throws {
        let (store, tmp) = makeStore()
        defer { try? FileManager.default.removeItem(at: tmp) }
        var original = SavedImportMapping.newDraft()
        original.name = "Original"
        let saved = try store.save(original)
        let copy = try store.duplicate(id: saved.id)
        XCTAssertNotNil(copy)
        XCTAssertNotEqual(copy?.id, saved.id, "Duplicate must get a fresh id")
        XCTAssertTrue(copy?.name.hasSuffix("(copy)") ?? false)
        XCTAssertEqual(store.mappings.count, 2)
    }

    func testEnvelopeRoundTrip() throws {
        var draft = SavedImportMapping.newDraft()
        draft.name = "Round trip"
        draft.fieldMappings = [
            SavedImportMapping.FieldMapping(
                id: UUID().uuidString,
                source: .column("col_a"),
                targetKey: "name",
                expectedKind: .text,
                transforms: [.trim, .lowercase],
                defaultValue: .string("(none)"),
                onError: .fillDefault
            )
        ]
        let env = SavedImportMappingEnvelope(draft)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(env)
        let decoded = try JSONDecoder().decode(SavedImportMappingEnvelope.self, from: data)
        XCTAssertEqual(decoded.format, "purplelife.import-mapping.v1")
        XCTAssertEqual(decoded.mapping.name, "Round trip")
        XCTAssertEqual(decoded.mapping.fieldMappings.count, 1)
        XCTAssertEqual(decoded.mapping.fieldMappings[0].targetKey, "name")
    }

    func testDecodeBarePayloadFallback() throws {
        // Forward-compat: readers accept a bare `SavedImportMapping`
        // dict, no envelope. The plan's design decision #4 calls
        // this out explicitly.
        let draft = SavedImportMapping.newDraft()
        let encoder = JSONEncoder()
        let bareData = try encoder.encode(draft)
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bare-\(UUID().uuidString).json")
        try bareData.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let restored = try MappingStore.decodeFile(at: tmp, key: nil)
        XCTAssertEqual(restored.id, draft.id)
    }
}
