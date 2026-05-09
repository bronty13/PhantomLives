import XCTest
@testable import PurpleDedupCore

final class UnionFindTests: XCTestCase {

    func testInitiallyDisjoint() {
        var uf = UnionFind(count: 5)
        for i in 0..<5 {
            XCTAssertEqual(uf.find(i), i)
        }
    }

    func testUnionMergesAndIsTransitive() {
        var uf = UnionFind(count: 6)
        XCTAssertTrue(uf.union(0, 1))
        XCTAssertTrue(uf.union(1, 2))
        XCTAssertTrue(uf.union(3, 4))
        XCTAssertFalse(uf.union(0, 2), "0 and 2 already share a root via 1")

        XCTAssertEqual(uf.find(0), uf.find(2))
        XCTAssertEqual(uf.find(3), uf.find(4))
        XCTAssertNotEqual(uf.find(0), uf.find(3))
        XCTAssertNotEqual(uf.find(0), uf.find(5))
    }
}
