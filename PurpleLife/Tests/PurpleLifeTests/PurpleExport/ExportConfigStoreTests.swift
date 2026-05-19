import XCTest
@testable import PurpleLife

@MainActor
final class ExportConfigStoreTests: XCTestCase {

    private func makeStore() -> (ExportConfigStore, URL) {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ExportConfigStoreTests-\(UUID().uuidString)", isDirectory: true)
        let store = ExportConfigStore(directoryURL: tmp, keyResolver: { nil })
        return (store, tmp)
    }

    func testSaveAndReload() throws {
        let (store, tmp) = makeStore()
        defer { try? FileManager.default.removeItem(at: tmp) }
        var draft = SavedExportConfig.newDraft()
        draft.name = "Test"
        let saved = try store.save(draft)
        let restored = ExportConfigStore(directoryURL: tmp, keyResolver: { nil })
        XCTAssertEqual(restored.configs.count, 1)
        XCTAssertEqual(restored.configs.first?.id, saved.id)
        XCTAssertEqual(restored.configs.first?.name, "Test")
    }

    func testMalformedFileSkipped() throws {
        let (store, tmp) = makeStore()
        defer { try? FileManager.default.removeItem(at: tmp) }
        var good = SavedExportConfig.newDraft()
        good.name = "Good"
        _ = try store.save(good)
        let bad = tmp.appendingPathComponent("garbage.purpleexport.json")
        try "not json".write(to: bad, atomically: true, encoding: .utf8)
        let restored = ExportConfigStore(directoryURL: tmp, keyResolver: { nil })
        XCTAssertEqual(restored.configs.count, 1)
    }

    func testEnvelopeRoundTrip() throws {
        var draft = SavedExportConfig.newDraft()
        draft.name = "Roundtrip"
        draft.format = .json
        let env = SavedExportConfigEnvelope(draft)
        let encoder = JSONEncoder()
        let data = try encoder.encode(env)
        let decoded = try JSONDecoder().decode(SavedExportConfigEnvelope.self, from: data)
        XCTAssertEqual(decoded.format, "purplelife.export-config.v1")
        XCTAssertEqual(decoded.config.name, "Roundtrip")
        XCTAssertEqual(decoded.config.format, .json)
    }

    func testDecodeBarePayloadFallback() throws {
        let draft = SavedExportConfig.newDraft()
        let bare = try JSONEncoder().encode(draft)
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bare-\(UUID().uuidString).json")
        try bare.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let restored = try ExportConfigStore.decodeFile(at: tmp, key: nil)
        XCTAssertEqual(restored.id, draft.id)
    }
}
