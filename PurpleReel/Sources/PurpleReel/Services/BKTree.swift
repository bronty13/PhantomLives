import Foundation

/// Burkhard-Keller tree for fast metric-space neighbor search over
/// integer-distance hashes (Hamming distance on UInt64 in our case).
///
/// Build is O(n log n) on uniform data, query is O(log n) expected
/// for small thresholds. PurpleDedup uses a similar structure to
/// avoid O(n²) when clustering hundreds of thousands of perceptual
/// hashes. For PurpleReel scale (a few thousand clips at most)
/// O(n²) was fine, but this scales us up to libraries with tens of
/// thousands of clips without changing the API.
final class BKTree {
    private final class Node {
        let value: UInt64
        let payload: Int      // index into the caller's flat hash array
        var children: [Int: Node] = [:]   // distance → child
        init(value: UInt64, payload: Int) {
            self.value = value
            self.payload = payload
        }
    }

    private var root: Node?
    private(set) var count = 0

    func insert(value: UInt64, payload: Int) {
        guard let root else {
            self.root = Node(value: value, payload: payload)
            count += 1
            return
        }
        var current = root
        while true {
            let d = Self.hamming(current.value, value)
            if let child = current.children[d] {
                current = child
            } else {
                current.children[d] = Node(value: value, payload: payload)
                count += 1
                return
            }
        }
    }

    /// Return all payload indices whose stored value is within
    /// `threshold` Hamming distance of `value`.
    func neighbors(of value: UInt64, within threshold: Int) -> [Int] {
        var matches: [Int] = []
        guard let root else { return matches }
        var stack: [Node] = [root]
        while let node = stack.popLast() {
            let d = Self.hamming(node.value, value)
            if d <= threshold { matches.append(node.payload) }
            // Triangle inequality: children at distance `cd` from
            // `node` can only contain matches if |cd - d| <= threshold.
            let lo = max(0, d - threshold)
            let hi = d + threshold
            for (cd, child) in node.children where cd >= lo && cd <= hi {
                stack.append(child)
            }
        }
        return matches
    }

    @inline(__always)
    static func hamming(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }
}
