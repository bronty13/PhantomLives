import XCTest
@testable import PurpleDedupCore

final class BKTreeTests: XCTestCase {

    func testInsertAndExactMatch() {
        var tree = BKTree<Int>()
        tree.insert(0xDEADBEEF, payload: 1)
        tree.insert(0xDEADBEEF, payload: 2)   // duplicate key → both payloads at distance 0
        tree.insert(0x12345678, payload: 3)

        let exact = tree.neighbors(of: 0xDEADBEEF, withinDistance: 0)
        XCTAssertEqual(Set(exact.map(\.payload)), Set([1, 2]))
        XCTAssertTrue(exact.allSatisfy { $0.distance == 0 })
    }

    func testThresholdControlsBreadth() {
        var tree = BKTree<String>()
        tree.insert(0b0000, payload: "zero")
        tree.insert(0b0001, payload: "one_bit")    // distance 1 from 0
        tree.insert(0b0011, payload: "two_bits")   // distance 2 from 0
        tree.insert(0b0111, payload: "three_bits") // distance 3 from 0
        tree.insert(0b1111, payload: "four_bits")  // distance 4 from 0

        let close = Set(tree.neighbors(of: 0, withinDistance: 1).map(\.payload))
        XCTAssertEqual(close, Set(["zero", "one_bit"]))

        let mid = Set(tree.neighbors(of: 0, withinDistance: 3).map(\.payload))
        XCTAssertEqual(mid, Set(["zero", "one_bit", "two_bits", "three_bits"]))

        let all = Set(tree.neighbors(of: 0, withinDistance: 64).map(\.payload))
        XCTAssertEqual(all.count, 5)
    }

    func testEmptyTreeReturnsNoNeighbors() {
        let tree = BKTree<Int>()
        XCTAssertTrue(tree.neighbors(of: 0, withinDistance: 64).isEmpty)
    }

    func testCorrectnessAgainstBruteForce() {
        // Random sanity check: for 200 random hashes and 50 random queries, the BK-tree
        // must return the same set as a linear scan. If this ever fails, the triangle-
        // inequality pruning is wrong.
        var rng = SystemRandomNumberGenerator()
        var tree = BKTree<Int>()
        var hashes: [UInt64] = []
        for i in 0..<200 {
            let h = UInt64.random(in: 0...UInt64.max, using: &rng)
            tree.insert(h, payload: i)
            hashes.append(h)
        }
        for _ in 0..<50 {
            let q = UInt64.random(in: 0...UInt64.max, using: &rng)
            let t = Int.random(in: 0...12, using: &rng)
            let bruteForce: Set<Int> = Set(
                hashes.enumerated()
                    .filter { PerceptualHash.hammingDistance($0.element, q) <= t }
                    .map(\.offset)
            )
            let viaTree = Set(tree.neighbors(of: q, withinDistance: t).map(\.payload))
            XCTAssertEqual(bruteForce, viaTree, "BK-tree disagrees with brute force at threshold \(t)")
        }
    }
}
