import XCTest
@testable import PurpleDiary

/// Exercises the Settings → General sample-data facility. Under XCTest the
/// support dir (and thus `DatabaseService.shared` + settings.json) routes to a
/// per-process temp directory, so these operate on a disposable DB.
@MainActor
final class SampleDataTests: XCTestCase {

    private func cleanStore() -> SettingsStore {
        let store = SettingsStore()
        var s = store.settings
        s.sampleDataIds = []
        store.settings = s
        store.save()
        return store
    }

    func testPopulateInsertsExactlyNAndTracksIds() throws {
        let store = cleanStore()
        let before = try DatabaseService.shared.fetchAllEntries().count
        let n = SampleDataService.populate(count: 7, settingsStore: store)
        XCTAssertEqual(n, 7)
        XCTAssertEqual(store.settings.sampleDataIds.count, 7)
        let after = try DatabaseService.shared.fetchAllEntries().count
        XCTAssertEqual(after - before, 7)
    }

    func testRemoveAllSamplesDeletesThemAndClearsList() throws {
        let store = cleanStore()
        _ = SampleDataService.populate(count: 5, settingsStore: store)
        // Delete one by hand first to prove remove tolerates already-gone ids.
        let firstId = store.settings.sampleDataIds[0]
        try DatabaseService.shared.deleteEntry(id: firstId)

        let before = try DatabaseService.shared.fetchAllEntries().count
        let removed = SampleDataService.removeAllSamples(settingsStore: store)
        XCTAssertEqual(removed, 4, "the 4 still-present sample entries are removed")
        XCTAssertEqual(store.settings.sampleDataIds.count, 0)
        let after = try DatabaseService.shared.fetchAllEntries().count
        XCTAssertEqual(before - after, 4)
    }
}
