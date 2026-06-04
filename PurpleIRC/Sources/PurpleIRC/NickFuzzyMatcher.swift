import Foundation

/// Fuzzy nick matching for the sidebar "Find … in logs" action.
///
/// IRC users keep showing up under decorated or renamed nicks — `john_doe`
/// today, `johndoe1` after a ghost, `johnny1` on a phone client, `jdough1`
/// somewhere else entirely. When the user right-clicks a nick and asks to
/// find that *person's* chat history, a plain substring search misses all of
/// those. This matcher normalises away the usual decoration and then scores
/// the remainder with a prefix-weighted similarity, because the one thing
/// nick variants reliably share is their leading characters.
///
/// Pure value type, no IRC dependencies — exercised directly by
/// `NickFuzzyMatcherTests`.
enum NickFuzzyMatcher {

    // MARK: - Normalisation

    /// Characters IRC clients/networks routinely sprinkle around a base nick
    /// (away markers, alt-nick padding, RFC-1459 "special" chars). Stripping
    /// them collapses `john_doe`, `john|doe`, `[john]doe` to one root.
    private static let decoration = Set("_|`^-[]{}\\")

    /// Common trailing away/status suffixes that aren't part of the identity.
    private static let awaySuffixes = ["away", "afk", "gone", "zzz", "brb", "busy"]

    /// Reduce a nick to a comparable root: lowercase, drop decoration chars,
    /// strip a trailing away-suffix, then strip trailing digits (alt padding
    /// like the `1` in `johndoe1`). Order matters — suffix before digits so
    /// `john|away2` → `john`.
    ///
    /// Examples: `john_doe`→`johndoe`, `johndoe1`→`johndoe`,
    /// `johnny1`→`johnny`, `jdough1`→`jdough`, `[John]^away`→`john`.
    static func normalize(_ nick: String) -> String {
        var s = nick.lowercased().filter { !decoration.contains($0) }
        // Peel a trailing away-suffix if one is present (after decoration is
        // gone the separator is already removed, so it's a bare suffix).
        for suffix in awaySuffixes where s.hasSuffix(suffix) && s.count > suffix.count {
            s = String(s.dropLast(suffix.count))
            break
        }
        while let last = s.last, last.isNumber {
            s.removeLast()
        }
        return s
    }

    // MARK: - Similarity

    /// Similarity of two nicks in `0...1`, computed on their normalised roots.
    /// Identical roots short-circuit to `1.0`; otherwise it's Jaro-Winkler,
    /// which rewards a shared prefix heavily — exactly the signal that holds
    /// across nick variants.
    static func similarity(_ a: String, _ b: String) -> Double {
        let na = normalize(a), nb = normalize(b)
        if na.isEmpty || nb.isEmpty { return 0 }
        if na == nb { return 1 }
        return jaroWinkler(Array(na), Array(nb))
    }

    /// Decide whether `candidate` is a variant of `target` at the given
    /// fuzziness `threshold` (lower = looser). Three independent signals, any
    /// of which is enough:
    ///   • identical normalised roots,
    ///   • one root contains the other (≥ 3 chars, so `al`⊄`walter` noise is
    ///     excluded — mirrors the address-book matcher's guard),
    ///   • Jaro-Winkler similarity ≥ `threshold`.
    static func matches(target: String, candidate: String, threshold: Double) -> Bool {
        let t = normalize(target), c = normalize(candidate)
        guard !t.isEmpty, !c.isEmpty else { return false }
        if t == c { return true }
        if min(t.count, c.count) >= 3 && (t.contains(c) || c.contains(t)) { return true }
        return jaroWinkler(Array(t), Array(c)) >= threshold
    }

    /// Jaro-Winkler similarity on two character arrays (assumed already
    /// normalised/lowercased by callers). Standard algorithm: Jaro base, then
    /// a bonus of `0.1` per shared leading character (capped at 4).
    private static func jaroWinkler(_ s1: [Character], _ s2: [Character]) -> Double {
        let j = jaro(s1, s2)
        guard j > 0 else { return 0 }
        var prefix = 0
        for i in 0..<min(4, min(s1.count, s2.count)) {
            if s1[i] == s2[i] { prefix += 1 } else { break }
        }
        return j + Double(prefix) * 0.1 * (1 - j)
    }

    private static func jaro(_ s1: [Character], _ s2: [Character]) -> Double {
        let len1 = s1.count, len2 = s2.count
        if len1 == 0 && len2 == 0 { return 1 }
        if len1 == 0 || len2 == 0 { return 0 }
        // Half the length of the longer string, minus one — but never < 0.
        let matchDistance = max(0, max(len1, len2) / 2 - 1)
        var s1Matched = [Bool](repeating: false, count: len1)
        var s2Matched = [Bool](repeating: false, count: len2)
        var matches = 0
        for i in 0..<len1 {
            let start = max(0, i - matchDistance)
            let end = min(i + matchDistance + 1, len2)
            guard start < end else { continue }
            for j in start..<end where !s2Matched[j] && s1[i] == s2[j] {
                s1Matched[i] = true
                s2Matched[j] = true
                matches += 1
                break
            }
        }
        guard matches > 0 else { return 0 }
        // Count transpositions: walk the matched chars of both strings in
        // order; a mismatch at the same rank is half a transposition.
        var transpositions = 0
        var k = 0
        for i in 0..<len1 where s1Matched[i] {
            while !s2Matched[k] { k += 1 }
            if s1[i] != s2[k] { transpositions += 1 }
            k += 1
        }
        let m = Double(matches)
        let t = Double(transpositions) / 2
        return (m / Double(len1) + m / Double(len2) + (m - t) / m) / 3
    }

    // MARK: - Log-line author extraction

    /// Pull the author nick(s) out of a persisted log-line *body* (the text
    /// after `LogStore`'s ISO-8601 timestamp prefix has been stripped).
    ///
    /// Mirrors the shapes emitted by `ChatLine.toLogLine()`:
    ///   • `<nick> …`            incoming message
    ///   • `→nick→ …`            our own message
    ///   • `-nick- …`            notice
    ///   • `* nick …`            action  (also matches authorless `* info`
    ///                            lines — accepted; those are `isNoisyLogKind`
    ///                            and usually not persisted)
    ///   • `→ nick joined`       join     (arrow + space distinguishes it
    ///                            from the no-space self-message form)
    ///   • `← nick left/quit …`  part / quit
    ///   • `old → new`           rename — returns *both* nicks
    ///
    /// Authorless kinds (`MOTD`, `! error`, `topic:`, raw) yield `[]`.
    static func authors(ofLogLineBody body: String) -> [String] {
        let line = body.trimmingCharacters(in: .whitespaces)
        guard let first = line.first else { return [] }

        switch first {
        case "<":
            if let close = line.firstIndex(of: ">"), close > line.startIndex {
                return [token(line, after: line.index(after: line.startIndex), upTo: close)]
            }
        case "-":
            // Notice `-nick- …` — find the closing dash.
            let afterFirst = line.index(after: line.startIndex)
            if let close = line[afterFirst...].firstIndex(of: "-") {
                let nick = token(line, after: afterFirst, upTo: close)
                if !nick.isEmpty { return [nick] }
            }
        case "→":
            let afterArrow = line.index(after: line.startIndex)
            if afterArrow < line.endIndex, line[afterArrow] == " " {
                // Join: "→ nick joined" — author is the first word.
                return firstWord(in: line[afterArrow...]).map { [$0] } ?? []
            }
            // Self message: "→nick→ …" — author up to the next arrow.
            if let close = line[afterArrow...].firstIndex(of: "→") {
                return [token(line, after: afterArrow, upTo: close)]
            }
        case "←":
            // Part/quit: "← nick left/quit …" — first word after the arrow.
            let rest = line.dropFirst()
            return firstWord(in: rest).map { [$0] } ?? []
        case "*":
            // Action: "* nick …" — first word after the star.
            let rest = line.dropFirst()
            return firstWord(in: rest).map { [$0] } ?? []
        default:
            // Rename: "old → new" — two authors.
            if let arrow = line.range(of: " → ") {
                let old = String(line[..<arrow.lowerBound]).trimmingCharacters(in: .whitespaces)
                let new = String(line[arrow.upperBound...]).trimmingCharacters(in: .whitespaces)
                let pair = [old, new].filter { !$0.isEmpty && !$0.contains(" ") }
                if !pair.isEmpty { return pair }
            }
        }
        return []
    }

    private static func token(_ s: String, after start: String.Index, upTo end: String.Index) -> String {
        String(s[start..<end])
    }

    /// First whitespace-delimited word of a substring, or nil if blank.
    private static func firstWord(in s: Substring) -> String? {
        let trimmed = s.drop(while: { $0 == " " })
        let word = trimmed.prefix(while: { $0 != " " })
        return word.isEmpty ? nil : String(word)
    }
}
