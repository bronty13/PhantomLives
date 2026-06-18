import Foundation

/// Foundation-only mIRC / IRCv3 formatting utilities. This is the engine-side
/// counterpart to an app's view-time renderer: it strips formatting control
/// bytes to recover plain text for logging, matching, and notifications —
/// without pulling in SwiftUI/`AttributedString`/`Color` (which belong in the
/// app layer). Apps that render colored text keep their own renderer; they can
/// still call `stripFormatting` for the plain-text path.
public enum IRCText {
    // Formatting control bytes.
    private static let bold:    Character = "\u{02}"
    private static let italic:  Character = "\u{1D}"
    private static let underln: Character = "\u{1F}"
    private static let strike:  Character = "\u{1E}"
    private static let reverse: Character = "\u{16}"
    private static let reset:   Character = "\u{0F}"
    private static let color:   Character = "\u{03}"
    private static let mono:    Character = "\u{11}"
    private static let hexCol:  Character = "\u{04}"

    private static let controlSet: Set<Character> =
        [bold, italic, underln, strike, reverse, reset, color, mono, hexCol]

    /// Returns `raw` with every mIRC code stripped — suitable for bot matching,
    /// URL extraction against plain text, notifications, and logs.
    public static func stripFormatting(_ raw: String) -> String {
        var out = ""
        var i = raw.startIndex
        while i < raw.endIndex {
            let c = raw[i]
            if c == color {
                i = raw.index(after: i)
                i = consumeDigits(raw, at: i, max: 2)
                if i < raw.endIndex, raw[i] == "," {
                    let afterComma = raw.index(after: i)
                    let probe = consumeDigits(raw, at: afterComma, max: 2)
                    if probe > afterComma { i = probe }
                }
                continue
            }
            if c == hexCol {
                i = raw.index(after: i)
                i = consumeHex(raw, at: i, count: 6)
                if i < raw.endIndex, raw[i] == "," {
                    let afterComma = raw.index(after: i)
                    let probe = consumeHex(raw, at: afterComma, count: 6)
                    if probe > afterComma { i = probe }
                }
                continue
            }
            if controlSet.contains(c) {
                i = raw.index(after: i)
                continue
            }
            out.append(c)
            i = raw.index(after: i)
        }
        return out
    }

    private static func consumeDigits(_ s: String, at start: String.Index, max: Int) -> String.Index {
        var i = start
        var count = 0
        while count < max, i < s.endIndex, s[i].isASCII, s[i].isNumber {
            i = s.index(after: i)
            count += 1
        }
        return i
    }

    private static func consumeHex(_ s: String, at start: String.Index, count: Int) -> String.Index {
        var i = start
        var n = 0
        while n < count, i < s.endIndex, s[i].isHexDigit {
            i = s.index(after: i)
            n += 1
        }
        return n == count ? i : start
    }
}
