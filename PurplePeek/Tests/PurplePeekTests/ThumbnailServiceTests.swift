import XCTest
@testable import PurplePeek

final class ThumbnailServiceTests: XCTestCase {
    /// The shared-cache id MUST equal PeekServer's `sha1(file_path)[:16]`, or PurplePeek silently
    /// stops reusing PeekServer's warmed thumbnails. Literals verified against Python:
    ///   hashlib.sha1(p.encode()).hexdigest()[:16]
    func testSharedThumbIDMatchesPeekServer() {
        XCTAssertEqual(ThumbnailService.sharedThumbID(forPath: "/x/y.jpg"), "6799c3bd4969f3af")
        XCTAssertEqual(
            ThumbnailService.sharedThumbID(
                forPath: "/Volumes/REDONE/PurpleAttic/NEW PHOTOS TO REVIEW/20260614-231701/originals/2004/2004-04/DSCF0019 (1).JPG"),
            "836e2e8867cf1662")
    }

    func testSharedThumbIDFormat() {
        let id = ThumbnailService.sharedThumbID(forPath: "/a/b.heic")
        XCTAssertEqual(id.count, 16)
        XCTAssertTrue(id.allSatisfy { $0.isHexDigit })
        // deterministic + path-sensitive
        XCTAssertEqual(id, ThumbnailService.sharedThumbID(forPath: "/a/b.heic"))
        XCTAssertNotEqual(id, ThumbnailService.sharedThumbID(forPath: "/a/c.heic"))
    }
}
