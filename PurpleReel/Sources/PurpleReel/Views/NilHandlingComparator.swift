import Foundation

/// `SortComparator` for `Optional<Value>` where `Value: Comparable`,
/// with nil entries pushed to the end of the list in either sort
/// direction. Used by `BrowserView`'s click-to-sort table columns
/// for fields PurpleReel stores as optionals (Codec, Resolution,
/// FPS, Duration) — putting "Unknown" rows last keeps them out of
/// the way whether the user is sorting up or down.
///
/// Standard `KeyPathComparator(\.optional, order:)` flips nil to the
/// top in `.reverse` order, which surprises users — they expect nil
/// to mean "no data, ignore" rather than "highest value."
struct NilHandlingComparator<Value: Comparable>: SortComparator {
    typealias Compared = Value?

    var order: SortOrder = .forward

    func compare(_ lhs: Value?, _ rhs: Value?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (.none, .none): return .orderedSame
        case (.none, _):     return .orderedDescending   // nil last
        case (_, .none):     return .orderedAscending    // nil last
        case let (l?, r?):
            if l < r {
                return order == .forward ? .orderedAscending  : .orderedDescending
            }
            if l > r {
                return order == .forward ? .orderedDescending : .orderedAscending
            }
            return .orderedSame
        }
    }
}
