import XCTest
import SQLite3
@testable import PurpleAtticCore

final class LibraryGuardTests: XCTestCase {

    // MARK: readAssetCount — denominator excludes syndicated/trashed (regression)

    /// Build a throwaway Photos-shaped SQLite at `path`, running `ddl` then each row in `rows`.
    private func makeDB(_ ddl: String, _ rows: [String]) throws -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("pa-assets-\(UUID().uuidString).sqlite").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, ddl, nil, nil, nil), SQLITE_OK)
        for r in rows { XCTAssertEqual(sqlite3_exec(db, r, nil, nil, nil), SQLITE_OK, r) }
        return path
    }

    func testAssetCountExcludesSyndicatedAndTrashed() throws {
        // 3 own visible assets, 2 "Shared with You" (ZVISIBILITYSTATE=2), 1 trashed.
        let path = try makeDB(
            "CREATE TABLE ZASSET (ZVISIBILITYSTATE INTEGER, ZTRASHEDSTATE INTEGER);",
            [
                "INSERT INTO ZASSET VALUES (0,0);",
                "INSERT INTO ZASSET VALUES (0,0);",
                "INSERT INTO ZASSET VALUES (0,0);",
                "INSERT INTO ZASSET VALUES (2,0);",   // syndicated — excluded
                "INSERT INTO ZASSET VALUES (2,0);",   // syndicated — excluded
                "INSERT INTO ZASSET VALUES (0,1);",   // trashed — excluded
            ])
        defer { try? FileManager.default.removeItem(atPath: path) }
        // Only the 3 own visible, non-trashed assets count — not the raw 6.
        XCTAssertEqual(LibraryInspector.readAssetCount(path), 3)
    }

    func testAssetCountFallsBackWhenColumnsAbsent() throws {
        // Older/newer schema without the visibility/trashed columns → plain COUNT(*).
        let path = try makeDB(
            "CREATE TABLE ZASSET (Z_PK INTEGER);",
            ["INSERT INTO ZASSET VALUES (1);", "INSERT INTO ZASSET VALUES (2);"])
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertEqual(LibraryInspector.readAssetCount(path), 2)
    }

    // MARK: LibraryInspector threshold

    func testFullyDownloadedLibraryNotFlagged() {
        // originals on disk ≈ asset count → complete.
        XCTAssertFalse(LibraryInspector.isLikelyOptimized(originalsOnDisk: 60_000, totalAssets: 60_000))
        // Even slightly more originals than assets (edited/Live resources) → complete.
        XCTAssertFalse(LibraryInspector.isLikelyOptimized(originalsOnDisk: 61_500, totalAssets: 60_000))
    }

    func testOptimizedLibraryFlagged() {
        // Only a small local subset present → optimized.
        XCTAssertTrue(LibraryInspector.isLikelyOptimized(originalsOnDisk: 1_200, totalAssets: 60_000))
        // Just below the 90% line → flagged.
        XCTAssertTrue(LibraryInspector.isLikelyOptimized(originalsOnDisk: 53_000, totalAssets: 60_000))
    }

    func testJustAboveThresholdNotFlagged() {
        // 90%+ on disk → treated as complete (margin for resource-layout quirks).
        XCTAssertFalse(LibraryInspector.isLikelyOptimized(originalsOnDisk: 54_000, totalAssets: 60_000))
    }

    func testZeroAssetsNeverFlagged() {
        XCTAssertFalse(LibraryInspector.isLikelyOptimized(originalsOnDisk: 0, totalAssets: 0))
    }

    // MARK: originalsIncomplete is honest + non-alarming (no false "Optimize Storage" claim)

    func testIncompleteSummaryIsNeutralNotAlarming() {
        let insp = LibraryInspection(libraryPath: "/x", exists: true, originalsOnDisk: 100,
                                     totalAssets: 8000, readable: true)
        XCTAssertTrue(insp.originalsIncomplete)
        // Must NOT assert the setting or shout "INCOMPLETE"; must name both possibilities.
        XCTAssertFalse(insp.summary.contains("INCOMPLETE"))
        XCTAssertTrue(insp.summary.contains("still downloading"))
        XCTAssertTrue(insp.summary.contains("100 of 8000"))
    }

    func testFullyDownloadedSummaryUnchanged() {
        let insp = LibraryInspection(libraryPath: "/x", exists: true, originalsOnDisk: 8000,
                                     totalAssets: 8000, readable: true)
        XCTAssertFalse(insp.originalsIncomplete)
        XCTAssertTrue(insp.summary.contains("looks fully downloaded"))
    }

    func testResolveLibraryPathFallsBackToSystemLibrary() {
        let resolved = LibraryInspector.resolveLibraryPath(nil)
        XCTAssertTrue(resolved.hasSuffix("Pictures/Photos Library.photoslibrary"))
        XCTAssertEqual(LibraryInspector.resolveLibraryPath("/x/Custom.photoslibrary"),
                       "/x/Custom.photoslibrary")
    }

    // MARK: VaultStatus

    func testVaultNotConfiguredWhenBlank() {
        XCTAssertEqual(VaultStatus.check(path: nil), .notConfigured)
        XCTAssertEqual(VaultStatus.check(path: "   "), .notConfigured)
    }

    func testVaultNotMountedWhenPathMissing() {
        XCTAssertEqual(VaultStatus.check(path: "/Volumes/DefinitelyNotMounted-PurpleAttic"), .notMounted)
    }

    func testVaultReadyWhenWritableDirExists() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pa-vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(VaultStatus.check(path: dir.path), .ready)
    }
}
