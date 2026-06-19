import Foundation

/// Expands a user-defined command alias template against its arguments.
///
/// - `$1`…`$9` — positional arguments (1-based).
/// - `$2-` (a digit followed by `-`) — that argument through the end.
/// - `$*` — all arguments.
/// - If the template contains **no** `$` placeholder, the arguments are appended
///   space-separated — so a simple alias like `j → /join` lets `/j #x` become
///   `/join #x`.
///
/// Unreferenced positional args are dropped (mIRC-style); a placeholder with no
/// corresponding arg yields empty.
enum AliasExpander {
    static func expand(_ template: String, args: [String]) -> String {
        guard template.contains("$") else {
            return args.isEmpty ? template : template + " " + args.joined(separator: " ")
        }
        let chars = Array(template)
        var out = ""
        var i = 0
        while i < chars.count {
            if chars[i] == "$", i + 1 < chars.count {
                let next = chars[i + 1]
                if next == "*" {
                    out += args.joined(separator: " ")
                    i += 2; continue
                }
                if let n = next.wholeNumberValue, n >= 1 {
                    // `$n-` → from n to the end; `$n` → just n.
                    if i + 2 < chars.count, chars[i + 2] == "-" {
                        if n - 1 < args.count { out += args[(n - 1)...].joined(separator: " ") }
                        i += 3; continue
                    } else {
                        if n - 1 < args.count { out += args[n - 1] }
                        i += 2; continue
                    }
                }
            }
            out.append(chars[i])
            i += 1
        }
        return out
    }
}
