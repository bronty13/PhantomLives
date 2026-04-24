import Foundation

/// Evaluates `HighlightRule`s against an inbound message. Caches compiled
/// `NSRegularExpression` objects keyed by rule ID so hot chat channels don't
/// pay the compile cost per message. Callers invalidate the cache after the
/// user edits a rule by calling `clearCache()`.
@MainActor
final class HighlightMatcher {
    /// Result for a single matched rule: the rule itself plus every range it
    /// hit (NSRange over the code-stripped plain text). The UI uses the first
    /// result's color; every result still contributes to alert firing.
    struct Hit {
        let rule: HighlightRule
        let ranges: [NSRange]
    }

    private var compiled: [UUID: NSRegularExpression] = [:]

    /// Call after the user adds/edits/removes rules. Cheap — next match call
    /// recompiles on demand.
    func clearCache() {
        compiled.removeAll(keepingCapacity: true)
    }

    /// Run every enabled rule that's scoped to this network against `text`.
    /// Returns hits in rule-definition order so the UI sees a stable
    /// "first match wins" color choice.
    func evaluate(rules: [HighlightRule],
                  text: String,
                  networkID: UUID) -> [Hit] {
        let stripped = IRCFormatter.stripCodes(text)
        guard !stripped.isEmpty else { return [] }

        var hits: [Hit] = []
        for rule in rules {
            guard rule.enabled, !rule.pattern.isEmpty else { continue }
            if !rule.networks.isEmpty, !rule.networks.contains(networkID) { continue }

            let ranges = matches(of: rule, in: stripped)
            if !ranges.isEmpty {
                hits.append(Hit(rule: rule, ranges: ranges))
            }
        }
        return hits
    }

    // MARK: - Internal

    private func matches(of rule: HighlightRule, in haystack: String) -> [NSRange] {
        guard let regex = regex(for: rule) else { return [] }
        let full = NSRange(haystack.startIndex..., in: haystack)
        return regex.matches(in: haystack, options: [], range: full).map(\.range)
    }

    private func regex(for rule: HighlightRule) -> NSRegularExpression? {
        if let cached = compiled[rule.id] { return cached }
        var options: NSRegularExpression.Options = []
        if !rule.caseSensitive { options.insert(.caseInsensitive) }
        let pattern: String
        if rule.isRegex {
            pattern = rule.pattern
        } else {
            // Literal mode: escape the user's string so metacharacters are
            // treated as text, then wrap in word boundaries so "foo" doesn't
            // light up inside "foobar". Nick-chars (mIRC style: `-_[]{}|^\`)
            // are treated as word-like so patterns like "rob_" still match.
            let escaped = NSRegularExpression.escapedPattern(for: rule.pattern)
            pattern = "(?<![A-Za-z0-9_\\-\\[\\]{}|^\\\\])\(escaped)(?![A-Za-z0-9_\\-\\[\\]{}|^\\\\])"
        }
        do {
            let re = try NSRegularExpression(pattern: pattern, options: options)
            compiled[rule.id] = re
            return re
        } catch {
            // Invalid regex — treat as no-match. The Setup UI surfaces the
            // error inline so the user can fix it.
            return nil
        }
    }
}
