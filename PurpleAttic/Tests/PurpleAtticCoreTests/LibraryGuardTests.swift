import XCTest
@testable import PurpleAtticCore

final class LibraryGuardTests: XCTestCase {

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
