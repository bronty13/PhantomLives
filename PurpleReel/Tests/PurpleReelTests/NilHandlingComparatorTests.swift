import XCTest
@testable import PurpleReel

/// Coverage for the C15 nil-handling comparator used by the list-
/// view click-to-sort columns. The standard library's optional
/// Comparable conformance puts nil first; in PurpleReel's catalogue
/// "no data" rows are noise, so we push them to the end in both
/// sort directions.
final class NilHandlingComparatorTests: XCTestCase {

    func testAscendingPushesNilToEnd() {
        var c = NilHandlingComparator<Int>()
        c.order = .forward
        let values: [Int?] = [3, nil, 1, nil, 2]
        let sorted = values.sorted { c.compare($0, $1) == .orderedAscending }
        XCTAssertEqual(sorted, [1, 2, 3, nil, nil],
                        "Ascending sort should put nils last, not first")
    }

    func testDescendingAlsoPushesNilToEnd() {
        var c = NilHandlingComparator<Int>()
        c.order = .reverse
        let values: [Int?] = [3, nil, 1, nil, 2]
        let sorted = values.sorted { c.compare($0, $1) == .orderedAscending }
        XCTAssertEqual(sorted, [3, 2, 1, nil, nil],
                        "Descending sort should still put nils last (not flipped to front)")
    }

    func testEqualValuesReturnOrderedSame() {
        let c = NilHandlingComparator<Int>()
        XCTAssertEqual(c.compare(5, 5), .orderedSame)
    }

    func testBothNilReturnOrderedSame() {
        let c = NilHandlingComparator<Int>()
        XCTAssertEqual(c.compare(nil, nil), .orderedSame)
    }

    func testStringComparatorAlsoNilHandles() {
        // Sanity check that the comparator works for non-Int Value
        // types too. Codec column hits this.
        var c = NilHandlingComparator<String>()
        c.order = .forward
        let values: [String?] = ["b", nil, "a"]
        let sorted = values.sorted { c.compare($0, $1) == .orderedAscending }
        XCTAssertEqual(sorted, ["a", "b", nil])
    }
}
