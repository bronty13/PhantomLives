import XCTest
@testable import PurpleDedupCore

final class PhotoLibraryFilterTests: XCTestCase {

    func testDefaultFilterIsInactive() {
        let f = PhotoLibraryFilter()
        XCTAssertFalse(f.isActive,
                       "A blank filter should not constrain the scan")
        XCTAssertTrue(f.summary.isEmpty)
    }

    func testAlbumNamesActivatesFilter() {
        var f = PhotoLibraryFilter()
        f.albumNames = ["Family"]
        XCTAssertTrue(f.isActive)
        XCTAssertTrue(f.summary.contains("Family"))
    }

    func testEmptyAlbumNamesSetCountsAsConstraint() {
        // An empty set is still "non-nil" — the user said "filter by albums,
        // and selected zero of them." That should match nothing, which is a
        // valid (if useless) filter state. `isActive` returns true so the
        // resolver runs the empty-set fetch and returns an empty whitelist.
        var f = PhotoLibraryFilter()
        f.albumNames = []
        XCTAssertTrue(f.isActive)
    }

    func testFavoriteToggleActivatesFilter() {
        var f = PhotoLibraryFilter()
        f.requireFavorite = true
        XCTAssertTrue(f.isActive)
        XCTAssertTrue(f.summary.contains("favorites"))
    }

    func testIncludeHiddenActivatesFilter() {
        var f = PhotoLibraryFilter()
        f.includeHidden = true
        XCTAssertTrue(f.isActive)
        XCTAssertTrue(f.summary.contains("hidden"))
    }

    func testSubtypesActivatesFilter() {
        var f = PhotoLibraryFilter()
        f.includedSubtypes = ["Live Photo", "Screenshot"]
        XCTAssertTrue(f.isActive)
        XCTAssertTrue(f.summary.contains("Live Photo"))
        XCTAssertTrue(f.summary.contains("Screenshot"))
    }

    func testPersonNamesActivatesFilter() {
        var f = PhotoLibraryFilter()
        f.personNames = ["Ada Lovelace", "Grace Hopper"]
        XCTAssertTrue(f.isActive)
        XCTAssertTrue(f.summary.contains("Ada Lovelace"))
        XCTAssertTrue(f.summary.contains("Grace Hopper"))
    }

    func testCodableRoundTrip() throws {
        var f = PhotoLibraryFilter()
        f.albumNames = ["Family", "Vacation 2024"]
        f.personNames = ["Ada Lovelace"]
        f.includedSubtypes = ["Live Photo"]
        f.requireFavorite = true
        f.includeHidden = false

        let data = try JSONEncoder().encode(f)
        let decoded = try JSONDecoder().decode(PhotoLibraryFilter.self, from: data)
        XCTAssertEqual(f, decoded)
    }

    /// Older saved filters (pre-personNames) must decode cleanly with
    /// `personNames == nil`. Mirrors the existing tolerant-decoder pattern
    /// for `onlyHidden`.
    func testCodableBackwardCompatNoPersonNames() throws {
        let legacy = #"""
        {"requireFavorite":true,"includeHidden":false,"onlyHidden":false}
        """#
        let decoded = try JSONDecoder().decode(
            PhotoLibraryFilter.self,
            from: Data(legacy.utf8)
        )
        XCTAssertNil(decoded.personNames)
        XCTAssertTrue(decoded.requireFavorite)
    }

    func testCodableRoundTripDictionary() throws {
        // SettingsStore serialises a `[String: PhotoLibraryFilter]` map as
        // JSON in UserDefaults — round-trip through the same path.
        var f1 = PhotoLibraryFilter()
        f1.requireFavorite = true
        var f2 = PhotoLibraryFilter()
        f2.albumNames = ["Family"]
        let map: [String: PhotoLibraryFilter] = ["/path/A.photoslibrary": f1, "/path/B.photoslibrary": f2]

        let data = try JSONEncoder().encode(map)
        let decoded = try JSONDecoder().decode([String: PhotoLibraryFilter].self, from: data)
        XCTAssertEqual(map, decoded)
    }
}
