import XCTest
@testable import PurpleReel

final class BKTreeTests: XCTestCase {

    func testExactMatchFindsSelf() {
        let tree = BKTree()
        tree.insert(value: 0xDEADBEEF, payload: 0)
        let neighbors = tree.neighbors(of: 0xDEADBEEF, within: 0)
        XCTAssertEqual(neighbors, [0])
    }

    func testReturnsAllWithinThreshold() {
        let tree = BKTree()
        // 8 zero hash + 8 progressively-flipped neighbors.
        let values: [UInt64] = [
            0b00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000,
            0b00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000001,  // d=1
            0b00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000011,  // d=2
            0b00000000_00000000_00000000_00000000_00000000_00000000_00000000_00001111,  // d=4
            0b11111111_00000000_00000000_00000000_00000000_00000000_00000000_00000000,  // d=8
            0b11111111_11111111_11111111_11111111_11111111_11111111_11111111_11111111,  // d=64
        ]
        for (i, v) in values.enumerated() { tree.insert(value: v, payload: i) }
        let withinTwo = Set(tree.neighbors(of: 0, within: 2))
        XCTAssertEqual(withinTwo, [0, 1, 2])

        let withinFour = Set(tree.neighbors(of: 0, within: 4))
        XCTAssertEqual(withinFour, [0, 1, 2, 3])

        let withinAll = Set(tree.neighbors(of: 0, within: 64))
        XCTAssertEqual(withinAll, Set(0..<values.count))
    }

    /// Brute-force vs BK-tree on a 500-element synthetic set —
    /// neighbor results must agree at every threshold.
    func testMatchesBruteForceOnLargeSet() {
        var rng = SystemRandomNumberGenerator()
        let values: [UInt64] = (0..<500).map { _ in UInt64.random(in: 0...UInt64.max, using: &rng) }
        let tree = BKTree()
        for (i, v) in values.enumerated() { tree.insert(value: v, payload: i) }

        let query = values[42]
        for threshold in [2, 8, 20, 64] {
            let bk = Set(tree.neighbors(of: query, within: threshold))
            let bf = Set(values.enumerated().compactMap { i, v in
                BKTree.hamming(v, query) <= threshold ? i : nil
            })
            XCTAssertEqual(bk, bf,
                           "BK-tree and brute-force disagree at threshold \(threshold)")
        }
    }

    func testCountTracksInsertions() {
        let tree = BKTree()
        XCTAssertEqual(tree.count, 0)
        tree.insert(value: 1, payload: 0)
        tree.insert(value: 2, payload: 1)
        tree.insert(value: 3, payload: 2)
        XCTAssertEqual(tree.count, 3)
    }
}
