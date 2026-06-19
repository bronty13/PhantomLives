import SwiftUI

/// Renders mIRC / IRCv3 formatting codes into a SwiftUI `AttributedString` for
/// the message area — bold, italic, underline, strikethrough, reverse, reset,
/// the 16-color palette, and IRCv3 hex colors. This is the app-layer companion
/// to IRCKit's Foundation-only `IRCText.stripFormatting`: the engine recovers
/// plain text for matching/logs; this paints the colors Ircle was known for.
///
/// Adapted from PurpleIRC's `IRCFormatter` (same maintainer) — kept in the app
/// layer because it depends on SwiftUI `Color`/`Font`/`AttributedString`, which
/// must never leak into IRCKit.
enum MircRenderer {
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

    private struct Style {
        var bold = false
        var italic = false
        var underline = false
        var strike = false
        var fg: Color? = nil
        var bg: Color? = nil
    }

    /// Build an attributed run of `raw` in `baseColor`, using Monaco at `size`.
    /// Color codes override `baseColor`; absent codes leave text in `baseColor`.
    static func attributed(_ raw: String, size: Double, baseColor: Color) -> AttributedString {
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
                let newFg = style.bg; let newBg = style.fg
                style.fg = newFg; style.bg = newBg
                i = raw.index(after: i)
            case reset:
                style = Style(); i = raw.index(after: i)
            case mono:
                i = raw.index(after: i) // no distinct mono style; text is already monospaced
            case color:
                i = raw.index(after: i)
                let (fg, bg, next) = parseColorRun(raw, at: i, prevFg: style.fg, prevBg: style.bg)
                style.fg = fg; style.bg = bg; i = next
            case hexCol:
                i = raw.index(after: i)
                let (fg, bg, next) = parseHexColorRun(raw, at: i, prevFg: style.fg, prevBg: style.bg)
                style.fg = fg; style.bg = bg; i = next
            default:
                let runStart = i
                while i < raw.endIndex && !controlSet.contains(raw[i]) {
                    i = raw.index(after: i)
                }
                appendChunk(String(raw[runStart..<i]), style: style,
                            size: size, baseColor: baseColor, into: &out)
            }
        }
        return out
    }

    /// A plain attributed run (no code parsing) — for client-generated prefixes.
    static func plain(_ text: String, size: Double, color: Color,
                      bold: Bool = false) -> AttributedString {
        var s = AttributedString(text)
        s.font = bold ? Font.custom("Monaco", size: size).bold() : Font.custom("Monaco", size: size)
        s.foregroundColor = color
        return s
    }

    // MARK: - Internals

    private static func appendChunk(_ text: String, style: Style,
                                    size: Double, baseColor: Color,
                                    into out: inout AttributedString) {
        guard !text.isEmpty else { return }
        var chunk = AttributedString(text)
        var font = Font.custom("Monaco", size: size)
        if style.bold { font = font.bold() }
        if style.italic { font = font.italic() }
        chunk.font = font
        chunk.foregroundColor = style.fg ?? baseColor
        if let bg = style.bg { chunk.backgroundColor = bg }
        if style.underline { chunk.underlineStyle = .single }
        if style.strike { chunk.strikethroughStyle = .single }
        out.append(chunk)
    }

    private static func parseColorRun(_ s: String, at start: String.Index,
                                      prevFg: Color?, prevBg: Color?)
    -> (Color?, Color?, String.Index) {
        var i = start
        let fgStart = i
        i = consumeDigits(s, at: i, max: 2)
        let fgDigits = String(s[fgStart..<i])
        if fgDigits.isEmpty { return (nil, nil, i) }   // bare ^C resets color
        var bg = prevBg
        if i < s.endIndex, s[i] == "," {
            let afterComma = s.index(after: i)
            let probe = consumeDigits(s, at: afterComma, max: 2)
            if probe > afterComma {
                bg = paletteColor(Int(String(s[afterComma..<probe])) ?? 99) ?? prevBg
                i = probe
            }
        }
        let fg = paletteColor(Int(fgDigits) ?? 99) ?? prevFg
        return (fg, bg, i)
    }

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
        var i = start; var n = 0
        while n < max, i < s.endIndex, s[i].isASCII, s[i].isNumber {
            i = s.index(after: i); n += 1
        }
        return i
    }

    private static func consumeHex(_ s: String, at start: String.Index, count: Int) -> String.Index {
        var i = start; var n = 0
        while n < count, i < s.endIndex, s[i].isHexDigit {
            i = s.index(after: i); n += 1
        }
        return n == count ? i : start
    }

    private static func rgbColor(from hex: String) -> Color? {
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xFF) / 255.0,
                     green: Double((v >> 8) & 0xFF) / 255.0,
                     blue: Double(v & 0xFF) / 255.0)
    }

    /// Standard mIRC palette (0–15). Codes 16+ are valid IRCv3 but rare; treat
    /// as unknown and fall through to the previous/base color.
    private static func paletteColor(_ code: Int) -> Color? {
        switch code {
        case 0:  return Color(red: 1,    green: 1,    blue: 1)
        case 1:  return Color(red: 0,    green: 0,    blue: 0)
        case 2:  return Color(red: 0,    green: 0,    blue: 0.50)
        case 3:  return Color(red: 0,    green: 0.50, blue: 0)
        case 4:  return Color(red: 1,    green: 0,    blue: 0)
        case 5:  return Color(red: 0.50, green: 0.25, blue: 0)
        case 6:  return Color(red: 0.50, green: 0,    blue: 0.50)
        case 7:  return Color(red: 1,    green: 0.50, blue: 0)
        case 8:  return Color(red: 1,    green: 1,    blue: 0)
        case 9:  return Color(red: 0,    green: 1,    blue: 0)
        case 10: return Color(red: 0,    green: 0.50, blue: 0.50)
        case 11: return Color(red: 0,    green: 1,    blue: 1)
        case 12: return Color(red: 0,    green: 0,    blue: 1)
        case 13: return Color(red: 1,    green: 0,    blue: 1)
        case 14: return Color(red: 0.50, green: 0.50, blue: 0.50)
        case 15: return Color(red: 0.75, green: 0.75, blue: 0.75)
        default: return nil
        }
    }
}
