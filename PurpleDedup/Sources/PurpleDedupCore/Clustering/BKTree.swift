import Foundation

/// Burkhard-Keller tree on Hamming distance over UInt64 keys. Scales sub-linear neighbor
/// search by exploiting the metric's triangle inequality: a query at threshold T only
/// needs to descend into children whose stored distance to their parent is in
/// [d_query - T, d_query + T].
///
/// We index by integer distance because Hamming distance is integral and bounded
/// (0...64). This means children can live in a fixed-size dictionary keyed by Int. There
/// are no balancing tricks; a near-uniform random insertion order produces a tree of
/// depth O(log n) on typical workloads. For huge libraries (>1M images) we'd revisit
/// with a paged-to-disk variant, but Phase 2 targets ~100K images max.
///
/// Generic on the payload type so callers can index either file IDs (when the cache is
/// populated, Phase 4) or in-memory indices (Phase 2).
public struct BKTree<Payload: Hashable> {

    private final class Node {
        let key: UInt64
        var payloads: [Payload]              // multiple files can share the same hash
        var children: [Int: Node] = [:]      // keyed by Hamming distance to this node

        init(key: UInt64, payload: Payload) {
            self.key = key
            self.payloads = [payload]
        }
    }

    private var root: Node?
    public private(set) var count: Int = 0

    public init() {}

    public mutating func insert(_ key: UInt64, payload: Payload) {
        count += 1
        guard let root = root else {
            self.root = Node(key: key, payload: payload)
            return
        }
        var current = root
        while true {
            let d = PerceptualHash.hammingDistance(current.key, key)
            if d == 0 {
                current.payloads.append(payload)
                return
            }
            if let child = current.children[d] {
                current = child
            } else {
                current.children[d] = Node(key: key, payload: payload)
                return
            }
        }
    }

    /// Returns every payload whose stored key is within `threshold` Hamming distance of
    /// `target`. Order is unspecified — callers that care should sort by some other key.
    public func neighbors(of target: UInt64, withinDistance threshold: Int) -> [(payload: Payload, distance: Int)] {
        guard let root = root else { return [] }
        var results: [(Payload, Int)] = []
        // Iterative DFS over a stack; the recursion depth is bounded but we avoid the
        // call overhead and any risk of blowing the stack on pathological inputs.
        var stack: [Node] = [root]
        while let node = stack.popLast() {
            let d = PerceptualHash.hammingDistance(node.key, target)
            if d <= threshold {
                for p in node.payloads {
                    results.append((p, d))
                }
            }
            // Triangle inequality: if a child stored at distance k from `node`, then
            // |k - d| ≤ distance(child.key, target) ≤ k + d. We only descend into ranges
            // overlapping [0, threshold].
            let lo = max(0, d - threshold)
            let hi = d + threshold
            for (k, child) in node.children where k >= lo && k <= hi {
                stack.append(child)
            }
        }
        return results
    }
}
