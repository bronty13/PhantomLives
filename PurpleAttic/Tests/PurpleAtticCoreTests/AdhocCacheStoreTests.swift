import XCTest
@testable import PurpleAtticCore

/// Covers the GRDB-backed ad-hoc file cache: the refresh upsert+prune contract, queries used by the
/// browse UI/reports, and the frozen migration list (the PhantomLives immutable-migration guard,
/// GRDB analog of SideMolly's hash check). All runs against an in-memory database — no file touched.
final class AdhocCacheStoreTests: XCTestCase {

    private func rf(_ path: String, _ size: Int64, isDir: Bool = false) -> AdhocRemoteFile {
        AdhocRemoteFile(path: path, name: (path as NSString).lastPathComponent, size: size,
                        modTime: Date(timeIntervalSince1970: 1_700_000_000), isDir: isDir)
    }

    // MARK: - Migration guard

    func testMigrationIdentifiersAreFrozen() {
        // Append new identifiers when you add a migration; never edit or remove a shipped one.
        XCTAssertEqual(AdhocCacheStore.migrationIdentifiers, ["v1-create-adhoc-file"])
    }

    func testStoreOpensAndStartsEmpty() throws {
        let store = try AdhocCacheStore(inMemory: true)
        XCTAssertEqual(try store.count(), 0)
        XCTAssertEqual(try store.totalSize(), 0)
        XCTAssertTrue(try store.allFiles().isEmpty)
    }

    // MARK: - Refresh: upsert + prune

    func testReplaceFromListingUpsertsAndPrunes() throws {
        let store = try AdhocCacheStore(inMemory: true)

        try store.replaceFromListing([rf("a/x.pdf", 100), rf("b.txt", 50)],
                                     refreshedAt: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(try store.count(), 2)
        XCTAssertEqual(try store.totalSize(), 150)

        // Next refresh: x.pdf changed (200), c.txt is new, b.txt has disappeared from the remote.
        try store.replaceFromListing([rf("a/x.pdf", 200), rf("c.txt", 7)],
                                     refreshedAt: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(try store.count(), 2, "b.txt (not seen this refresh) must be pruned")
        XCTAssertEqual(try store.totalSize(), 207, "x.pdf's size must be updated, not duplicated")

        let files = try store.allFiles()
        XCTAssertEqual(files.map(\.path), ["a/x.pdf", "c.txt"], "default order is by path")
        XCTAssertEqual(files.first(where: { $0.path == "a/x.pdf" })?.size, 200)
        XCTAssertNil(files.first(where: { $0.path == "b.txt" }))
    }

    func testEmptyListingPrunesEverything() throws {
        let store = try AdhocCacheStore(inMemory: true)
        try store.replaceFromListing([rf("a.txt", 1)], refreshedAt: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(try store.count(), 1)
        try store.replaceFromListing([], refreshedAt: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(try store.count(), 0, "an empty remote listing must clear the cache")
    }

    func testTotalSizeExcludesDirectories() throws {
        let store = try AdhocCacheStore(inMemory: true)
        try store.replaceFromListing([rf("dir", -1, isDir: true), rf("dir/a.txt", 42)],
                                     refreshedAt: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(try store.totalSize(), 42, "directory rows (size -1) must not skew the total")
    }

    // MARK: - remove / search

    func testRemoveDropsOneRow() throws {
        let store = try AdhocCacheStore(inMemory: true)
        try store.replaceFromListing([rf("a.txt", 1), rf("b.txt", 2)],
                                     refreshedAt: Date(timeIntervalSince1970: 1000))
        try store.remove(path: "a.txt")
        XCTAssertEqual(try store.count(), 1)
        XCTAssertEqual(try store.allFiles().map(\.path), ["b.txt"])
    }

    func testSearchIsCaseInsensitiveSubstring() throws {
        let store = try AdhocCacheStore(inMemory: true)
        try store.replaceFromListing([rf("Invoices/2026.pdf", 10), rf("photos/cat.jpg", 20)],
                                     refreshedAt: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(try store.search("invoice").map(\.path), ["Invoices/2026.pdf"])
        XCTAssertEqual(try store.search("CAT").map(\.path), ["photos/cat.jpg"])
        XCTAssertEqual(try store.search("").count, 2, "empty query returns everything")
    }
}
