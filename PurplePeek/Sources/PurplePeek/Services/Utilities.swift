import Foundation

extension Array {
    /// Split into consecutive chunks of at most `size` elements. Used to batch large scan
    /// upserts so each write transaction stays small and the UI can breathe between them.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
