import Foundation

/// Disjoint-set / union-find with path compression + union-by-rank. Used by the
/// perceptual clusterer to merge files connected by pairwise BK-tree neighbor matches
/// into transitive clusters. Both operations are effectively O(α(n)) which is, in
/// practice, constant time.
public struct UnionFind {
    private var parent: [Int]
    private var rank: [Int]

    public init(count: Int) {
        parent = Array(0..<count)
        rank = Array(repeating: 0, count: count)
    }

    public mutating func find(_ x: Int) -> Int {
        var x = x
        while parent[x] != x {
            parent[x] = parent[parent[x]]   // path compression (one-step splay)
            x = parent[x]
        }
        return x
    }

    @discardableResult
    public mutating func union(_ a: Int, _ b: Int) -> Bool {
        let ra = find(a)
        let rb = find(b)
        if ra == rb { return false }
        if rank[ra] < rank[rb] {
            parent[ra] = rb
        } else if rank[ra] > rank[rb] {
            parent[rb] = ra
        } else {
            parent[rb] = ra
            rank[ra] += 1
        }
        return true
    }
}
