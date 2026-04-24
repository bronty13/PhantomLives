import Foundation
import SwiftUI

/// Parses mIRC formatting / color codes and IRCv3 link-detects URLs, producing
/// an AttributedString suitable for SwiftUI Text. Raw text (with codes intact)
/// stays in `ChatLine.text` — this is a view-time transform. `stripCodes` is
/// also exposed for bot/matching use.
enum IRCFormatter {
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

    /// Render `raw` with both mIRC codes and URL link detection applied.
    /// Tintable at the call site via `linkColor`.
    static func renderWithLinks(_ raw: String, linkColor: Color = .accentColor) -> AttributedString {
        var attr = render(raw)
        let plain = String(attr.characters)
        guard !plain.isEmpty,
              let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return attr
        }
        let nsRange = NSRange(plain.startIndex..<plain.endIndex, in: plain)
        detector.enumerateMatches(in: plain, options: [], range: nsRange) { match, _, _ in
            guard let match, let url = match.url,
                  let swiftRange = Range(match.range, in: plain) else { return }
            let startOffset = plain.distance(from: plain.startIndex, to: swiftRange.lowerBound)
            let length = plain.distance(from: swiftRange.lowerBound, to: swiftRange.upperBound)
            let s = attr.characters.index(attr.characters.startIndex, offsetBy: startOffset)
            let e = attr.characters.index(s, offsetBy: length)
            var container = AttributeContainer()
            container.link = url
            container.underlineStyle = .single
            container.foregroundColor = linkColor
            attr[s..<e].mergeAttributes(container)
        }
        return attr
    }

    static func render(_ raw: String) -> AttributedString {
        var out = AttributedString()
        var style = Style()

        var i = raw.startIndex
        while i < raw.endIndex {
            let c = raw[i]
            switch c {
            case bold:    style.bold.toggle();      i = raw.index(after: i)
            case italic:  style.italic.toggle();    i = raw.index(after: i)
            case underln: style.underline.toggle(); i = raw.index(after: i)
            case strike:  style.strike.toggle();    i = raw.index(after: i)
            case reverse:
                // swap fg/bg
                let newFg = style.bg
                let newBg = style.fg
                style.fg = newFg
                style.bg = newBg
                i = raw.index(after: i)
            case reset:
                style = Style()
                i = raw.index(after: i)
            case mono:
                // no-op; we don't have a monospace style distinct from italic/bold toggles
                i = raw.index(after: i)
            case color:
                i = raw.index(after: i)
                let (fg, bg, nextIdx) = parseColorRun(raw, at: i, prevFg: style.fg, prevBg: style.bg)
                style.fg = fg
                style.bg = bg
                i = nextIdx
            case hexCol:
                i = raw.index(after: i)
                let (fg, bg, nextIdx) = parseHexColorRun(raw, at: i, prevFg: style.fg, prevBg: style.bg)
                style.fg = fg
                style.bg = bg
                i = nextIdx
            default:
                // Accumulate a plain-text run up to the next control byte.
                let runStart = i
                while i < raw.endIndex && !controlSet.contains(raw[i]) {
                    i = raw.index(after: i)
                }
                let chunk = String(raw[runStart..<i])
                appendChunk(chunk, style: style, into: &out)
            }
        }
        return out
    }

    /// Returns `raw` with every mIRC code stripped — suitable for bot matching,
    /// URL extraction against plain text, and logs.
    static func stripCodes(_ raw: String) -> String {
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

    // MARK: - Internal

    private struct Style {
        var bold      = false
        var italic    = false
        var underline = false
        var strike    = false
        var fg: Color? = nil
        var bg: Color? = nil
    }

    private static func appendChunk(_ text: String, style: Style, into out: inout AttributedString) {
        guard !text.isEmpty else { return }
        var chunk = AttributedString(text)
        if style.bold && style.italic {
            chunk.font = .body.bold().italic()
        } else if style.bold {
            chunk.font = .body.bold()
        } else if style.italic {
            chunk.font = .body.italic()
        }
        if style.underline { chunk.underlineStyle = .single }
        if style.strike    { chunk.strikethroughStyle = .single }
        if let fg = style.fg { chunk.foregroundColor = fg }
        if let bg = style.bg { chunk.backgroundColor = bg }
        out.append(chunk)
    }

    /// Parse `^C[fg[,bg]]` where fg/bg are 1–2 digit decimal codes. Empty
    /// arguments (a bare `^C`) reset foreground/background to nil.
    private static func parseColorRun(_ s: String, at start: String.Index,
                                      prevFg: Color?, prevBg: Color?)
    -> (Color?, Color?, String.Index) {
        var i = start
        let fgStart = i
        i = consumeDigits(s, at: i, max: 2)
        let fgDigits = String(s[fgStart..<i])
        if fgDigits.isEmpty {
            return (nil, nil, i)
        }
        var bg = prevBg
        if i < s.endIndex, s[i] == "," {
            let afterComma = s.index(after: i)
            let bgStart = afterComma
            let probe = consumeDigits(s, at: bgStart, max: 2)
            if probe > bgStart {
                let bgDigits = String(s[bgStart..<probe])
                bg = paletteColor(Int(bgDigits) ?? 99) ?? prevBg
                i = probe
            }
        }
        let fg = paletteColor(Int(fgDigits) ?? 99) ?? prevFg
        return (fg, bg, i)
    }

    /// Parse `^D<6-hex-fg>[,<6-hex-bg>]` (IRCv3 extended colors).
    private static func parseHexColorRun(_ s: String, at start: String.Index,
                                         prevFg: Color?, prevBg: Color?)
    -> (Color?, Color?, String.Index) {
        var i = start
        let fgStart = i
        i = consumeHex(s, at: i, count: 6)
        guard i > fgStart else { return (prevFg, prevBg, i) }
        let fg = rgbColor(from: String(s[fgStart..<i])) ?? prevFg
        var bg = prevBg
        if i < s.endIndex, s[i] == "," {
            let afterComma = s.index(after: i)
            let probe = consumeHex(s, at: afterComma, count: 6)
            if probe > afterComma {
                bg = rgbColor(from: String(s[afterComma..<probe])) ?? prevBg
                i = probe
            }
        }
        return (fg, bg, i)
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

    private static func rgbColor(from hex: String) -> Color? {
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8)  & 0xFF) / 255.0
        let b = Double( v        & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    /// Standard mIRC palette (0–15). IRC colors 16+ are defined by IRCv3 but
    /// rarely used; treat them as unknown and fall through.
    private static func paletteColor(_ code: Int) -> Color? {
        switch code {
        case 0:  return Color(red: 1,    green: 1,    blue: 1)     // white
        case 1:  return Color(red: 0,    green: 0,    blue: 0)     // black
        case 2:  return Color(red: 0,    green: 0,    blue: 0.50)  // blue (navy)
        case 3:  return Color(red: 0,    green: 0.50, blue: 0)     // green
        case 4:  return Color(red: 1,    green: 0,    blue: 0)     // red
        case 5:  return Color(red: 0.50, green: 0.25, blue: 0)     // brown (maroon)
        case 6:  return Color(red: 0.50, green: 0,    blue: 0.50)  // purple
        case 7:  return Color(red: 1,    green: 0.50, blue: 0)     // orange
        case 8:  return Color(red: 1,    green: 1,    blue: 0)     // yellow
        case 9:  return Color(red: 0,    green: 1,    blue: 0)     // light green
        case 10: return Color(red: 0,    green: 0.50, blue: 0.50)  // teal
        case 11: return Color(red: 0,    green: 1,    blue: 1)     // cyan
        case 12: return Color(red: 0,    green: 0,    blue: 1)     // light blue
        case 13: return Color(red: 1,    green: 0,    blue: 1)     // pink
        case 14: return Color(red: 0.50, green: 0.50, blue: 0.50)  // grey
        case 15: return Color(red: 0.75, green: 0.75, blue: 0.75)  // light grey
        default: return nil
        }
    }
}
