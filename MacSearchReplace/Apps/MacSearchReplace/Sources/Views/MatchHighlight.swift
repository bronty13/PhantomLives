import SwiftUI
import SnRCore

/// Builds an AttributedString that highlights every occurrence of `matchedText`
/// inside `line`. Mimics Funduc's bright in-line hit highlight.
enum MatchHighlight {

    static func attributed(
        line: String,
        matchedText: String,
        caseInsensitive: Bool,
        replacement: String? = nil,
        baseFont: Font = .system(.body, design: .monospaced)
    ) -> AttributedString {
        var out = AttributedString(line)
        out.font = baseFont
        guard !matchedText.isEmpty else { return out }

        let opts: String.CompareOptions = caseInsensitive ? [.caseInsensitive] : []
        var search = line.startIndex..<line.endIndex
        while let r = line.range(of: matchedText, options: opts, range: search) {
            if let aRange = Range(r, in: out) {
                if let repl = replacement, !repl.isEmpty {
                    // strikethrough original, then insert replacement after.
                    out[aRange].strikethroughStyle = .single
                    out[aRange].foregroundColor = .secondary
                    var insert = AttributedString(repl)
                    insert.font = baseFont
                    insert.backgroundColor = Color.green.opacity(0.30)
                    insert.foregroundColor = .primary
                    out.insert(insert, at: aRange.upperBound)
                } else {
                    out[aRange].backgroundColor = Color.yellow.opacity(0.55)
                    out[aRange].foregroundColor = .primary
                    out[aRange].font = baseFont.bold()
                }
            }
            search = r.upperBound..<line.endIndex
        }
        return out
    }
}
