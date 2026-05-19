import XCTest
@testable import PurpleReel

/// Coverage for the C22 RecentDestinations service. Each test isolates
/// the scope by clearing it on setUp, since UserDefaults is process-
/// wide and stale entries from a previous test run would pollute the
/// list-ordering assertions.
final class RecentDestinationsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        RecentDestinations.clear(.convert)
        RecentDestinations.clear(.combine)
    }

    override func tearDown() {
        RecentDestinations.clear(.convert)
        RecentDestinations.clear(.combine)
        super.tearDown()
    }

    func testEmptyListInitially() {
        XCTAssertTrue(RecentDestinations.list(.convert).isEmpty)
        XCTAssertTrue(RecentDestinations.list(.combine).isEmpty)
    }

    func testPushAppearsAtFront() {
        RecentDestinations.push(URL(fileURLWithPath: "/a/b"), scope: .convert)
        RecentDestinations.push(URL(fileURLWithPath: "/c/d"), scope: .convert)
        let list = RecentDestinations.list(.convert).map(\.path)
        XCTAssertEqual(list.first, "/c/d",
                        "Most-recent push should land at index 0")
    }

    func testDuplicateUrlMovesToFront() {
        RecentDestinations.push(URL(fileURLWithPath: "/a/b"), scope: .convert)
        RecentDestinations.push(URL(fileURLWithPath: "/c/d"), scope: .convert)
        RecentDestinations.push(URL(fileURLWithPath: "/a/b"), scope: .convert)
        let list = RecentDestinations.list(.convert).map(\.path)
        XCTAssertEqual(list, ["/a/b", "/c/d"],
                        "Re-pushing an existing path should move it to front, not duplicate")
    }

    func testCaseInsensitiveDedupe() {
        // macOS volumes are case-insensitive by default; "/Volumes/CardA"
        // and "/Volumes/carda" are the same folder. Repeated picks
        // with different casing shouldn't accumulate two entries.
        RecentDestinations.push(URL(fileURLWithPath: "/Volumes/CardA"), scope: .convert)
        RecentDestinations.push(URL(fileURLWithPath: "/volumes/carda"), scope: .convert)
        let list = RecentDestinations.list(.convert)
        XCTAssertEqual(list.count, 1,
                        "Case-insensitive duplicates should fold to one entry")
        XCTAssertEqual(list.first?.path, "/volumes/carda",
                        "Last-typed casing should win")
    }

    func testCapAtSix() {
        for i in 1...10 {
            RecentDestinations.push(URL(fileURLWithPath: "/p\(i)"),
                                     scope: .convert)
        }
        XCTAssertEqual(RecentDestinations.list(.convert).count, 6,
                        "Recents should cap at 6 entries (oldest evicted)")
        // Most recent (p10) at index 0; oldest still in (p5) at the
        // tail. p1-p4 should have been evicted.
        let paths = RecentDestinations.list(.convert).map(\.path)
        XCTAssertEqual(paths.first, "/p10")
        XCTAssertEqual(paths.last,  "/p5")
        XCTAssertFalse(paths.contains("/p1"))
    }

    func testScopesAreIndependent() {
        RecentDestinations.push(URL(fileURLWithPath: "/a"), scope: .convert)
        RecentDestinations.push(URL(fileURLWithPath: "/b"), scope: .combine)
        XCTAssertEqual(RecentDestinations.list(.convert).map(\.path), ["/a"])
        XCTAssertEqual(RecentDestinations.list(.combine).map(\.path), ["/b"])
    }

    func testClearRemovesAllEntries() {
        RecentDestinations.push(URL(fileURLWithPath: "/a"), scope: .convert)
        RecentDestinations.push(URL(fileURLWithPath: "/b"), scope: .convert)
        XCTAssertEqual(RecentDestinations.list(.convert).count, 2)
        RecentDestinations.clear(.convert)
        XCTAssertTrue(RecentDestinations.list(.convert).isEmpty)
    }
}
