import XCTest
@testable import PurpleDedupCore

/// Only the pure pieces of the import service are unit-testable: the actual
/// `PHAssetCreationRequest` / `performChanges` path needs a real authorized
/// Photos library and an interactive TCC grant, so it's covered by the manual
/// launch/verify step rather than here.
final class PhotoKitImportServiceTests: XCTestCase {

    func testClassifyForImportPartitionsByExtension() {
        let urls = [
            URL(fileURLWithPath: "/x/a.jpg"),
            URL(fileURLWithPath: "/x/b.HEIC"),
            URL(fileURLWithPath: "/x/c.mov"),
            URL(fileURLWithPath: "/x/d.MP4"),
            URL(fileURLWithPath: "/x/e.txt"),
            URL(fileURLWithPath: "/x/f"),
        ]
        let (photos, videos, skipped) = PhotoKitImportService.classifyForImport(urls: urls)
        XCTAssertEqual(Set(photos.map(\.lastPathComponent)), ["a.jpg", "b.HEIC"])
        XCTAssertEqual(Set(videos.map(\.lastPathComponent)), ["c.mov", "d.MP4"])
        XCTAssertEqual(Set(skipped.map(\.lastPathComponent)), ["e.txt", "f"])
    }

    func testImportResultSummary() {
        let a = URL(fileURLWithPath: "/x/a.jpg")
        let b = URL(fileURLWithPath: "/x/b.jpg")
        let c = URL(fileURLWithPath: "/x/c.txt")

        let full = PhotoKitImportService.ImportResult(
            imported: [a, b], failed: [(c, "boom")], skipped: [c], albumName: "Imported by PurpleDedup"
        )
        XCTAssertTrue(full.summary.contains("Imported 2"))
        XCTAssertTrue(full.summary.contains("Imported by PurpleDedup"))
        XCTAssertTrue(full.summary.contains("1 failed"))
        XCTAssertTrue(full.summary.contains("1 skipped"))

        let empty = PhotoKitImportService.ImportResult()
        XCTAssertEqual(empty.summary, "Nothing to import")

        let noAlbum = PhotoKitImportService.ImportResult(imported: [a], albumName: nil)
        XCTAssertTrue(noAlbum.summary.contains("Imported 1"))
        XCTAssertFalse(noAlbum.summary.contains("into"))
    }
}
