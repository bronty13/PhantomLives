import Foundation

/// Shared, reused `RelativeDateTimeFormatter`. Building one is expensive, and
/// the address-book sidebar / activity timeline / hostmask history rows each
/// used to allocate a fresh formatter per row on every render. One main-actor
/// instance, reused, fixes that — formatters aren't thread-safe, but every
/// caller here renders on the main actor.
@MainActor
enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    /// Abbreviated relative string (e.g. "3h ago") for `date` relative to now.
    static func string(_ date: Date, relativeTo reference: Date = Date()) -> String {
        formatter.localizedString(for: date, relativeTo: reference)
    }
}

/// Process-wide cache of compiled, case-insensitive `NSRegularExpression`s
/// keyed by pattern. Search views (channel list, seen list) recomputed their
/// filtered results — including a fresh regex compile — on every keystroke,
/// often twice per keystroke (once for filtering, once for the error label).
/// Caching keeps a complex pattern from recompiling on every character.
@MainActor
enum RegexCache {
    private static var cache: [String: NSRegularExpression?] = [:]

    /// Compiled case-insensitive regex for `pattern`, or nil when the pattern
    /// is invalid. The nil result is cached too, so an in-progress (invalid)
    /// pattern isn't recompiled on every keystroke either.
    static func caseInsensitive(_ pattern: String) -> NSRegularExpression? {
        if let hit = cache[pattern] { return hit }
        let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        cache[pattern] = re
        // Bound the cache — search patterns are transient as the user types.
        if cache.count > 256 { cache.removeAll(keepingCapacity: true) }
        return re
    }
}
