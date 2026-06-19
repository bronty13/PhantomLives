import Foundation

/// IRC hostmask matching for ignore lists and the like. Glob patterns use `*`
/// (any run) and `?` (any one char), matched case-insensitively against a full
/// `nick!user@host`. A bare pattern with no `!`/`@` is treated as a nick and
/// expanded to `<pattern>!*@*` (so `/ignore bob` ignores bob from anywhere).
public enum IRCMask {

    /// True if `hostmask` (a full `nick!user@host`, or just a nick) matches
    /// `pattern`.
    public static func matches(pattern: String, hostmask: String) -> Bool {
        let expanded = (pattern.contains("!") || pattern.contains("@")) ? pattern : pattern + "!*@*"
        return glob(Array(expanded.lowercased()), Array(hostmask.lowercased()))
    }

    /// Standard wildcard match (`*` and `?`) with backtracking — O(n·m) worst
    /// case, which is fine for hostmasks.
    static func glob(_ pattern: [Character], _ text: [Character]) -> Bool {
        var p = 0, t = 0
        var star = -1, mark = 0
        while t < text.count {
            if p < pattern.count, pattern[p] == "?" || pattern[p] == text[t] {
                p += 1; t += 1
            } else if p < pattern.count, pattern[p] == "*" {
                star = p; mark = t; p += 1
            } else if star != -1 {
                p = star + 1; mark += 1; t = mark
            } else {
                return false
            }
        }
        while p < pattern.count, pattern[p] == "*" { p += 1 }
        return p == pattern.count
    }
}
