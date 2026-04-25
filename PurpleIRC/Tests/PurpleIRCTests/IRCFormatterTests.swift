import Foundation
import Testing
@testable import PurpleIRC

/// Coverage for `IRCFormatter` — mIRC formatting code stripping, render
/// idempotence, and link detection. The render output is an
/// `AttributedString` whose string view should equal `stripCodes(raw)`
/// (every control byte gone, every printable kept). That equivalence
/// is the central invariant we test against — nick highlight ranges,
/// log lines, and bot matching all rely on it.
@Suite("IRCFormatter")
struct IRCFormatterTests {

    private let bold:    Character = "\u{02}"
    private let italic:  Character = "\u{1D}"
    private let underln: Character = "\u{1F}"
    private let strike:  Character = "\u{1E}"
    private let reverse: Character = "\u{16}"
    private let reset:   Character = "\u{0F}"
    private let color:   Character = "\u{03}"
    private let mono:    Character = "\u{11}"
    private let hexCol:  Character = "\u{04}"

    // MARK: - stripCodes

    @Test func stripPlainPassesThrough() {
        #expect(IRCFormatter.stripCodes("hello world") == "hello world")
    }

    @Test func stripBoldRemoved() {
        let raw = "\(bold)hello\(bold)"
        #expect(IRCFormatter.stripCodes(raw) == "hello")
    }

    @Test func stripItalicRemoved() {
        #expect(IRCFormatter.stripCodes("\(italic)foo\(italic)") == "foo")
    }

    @Test func stripUnderlineStrikeReverseMonoRemoved() {
        let raw = "\(underln)u\(strike)s\(reverse)r\(mono)m\(reset)"
        #expect(IRCFormatter.stripCodes(raw) == "usrm")
    }

    @Test func stripSimpleColorRemoved() {
        // ^C04hello^O
        let raw = "\(color)04hello\(reset)"
        #expect(IRCFormatter.stripCodes(raw) == "hello")
    }

    @Test func stripFgBgColorRemoved() {
        let raw = "\(color)04,12hello\(reset)"
        #expect(IRCFormatter.stripCodes(raw) == "hello")
    }

    @Test func stripSingleDigitColorRemoved() {
        let raw = "\(color)4hello\(reset)"
        #expect(IRCFormatter.stripCodes(raw) == "hello")
    }

    @Test func stripBareColorTerminator() {
        // ^C with no following digits = "reset color" — must be eaten cleanly.
        let raw = "fooBAR\(color)baz"
        #expect(IRCFormatter.stripCodes(raw) == "fooBARbaz")
    }

    @Test func stripHexColorRemoved() {
        // ^DRRGGBB
        let raw = "\(hexCol)112233hello"
        #expect(IRCFormatter.stripCodes(raw) == "hello")
    }

    @Test func stripHexColorWithBackground() {
        let raw = "\(hexCol)112233,445566hello"
        #expect(IRCFormatter.stripCodes(raw) == "hello")
    }

    @Test func stripCommaThatIsNotPartOfColorIsKept() {
        // After a single-digit fg color, a non-digit comma (like the comma
        // between sentences) must NOT be eaten. This is the classic mIRC
        // rendering ambiguity. We test that "Hello, world" survives.
        let raw = "\(color)4Hello\(reset), world"
        #expect(IRCFormatter.stripCodes(raw) == "Hello, world")
    }

    @Test func stripColorTrailingDigitIsKept() {
        // "^C04 cm" — color+digits, then a space and 'cm'. Numerals AFTER
        // the color sequence (max 2) belong to the color. Don't be greedy.
        let raw = "\(color)04 abc"
        #expect(IRCFormatter.stripCodes(raw) == " abc")
    }

    @Test func stripIsIdempotent() {
        let raw = "\(bold)\(color)04hi\(reset) world"
        let once = IRCFormatter.stripCodes(raw)
        #expect(IRCFormatter.stripCodes(once) == once)
    }

    @Test func stripPreservesUnicode() {
        let raw = "\(color)4Привет 🐉\(reset)"
        #expect(IRCFormatter.stripCodes(raw) == "Привет 🐉")
    }

    // MARK: - render

    @Test func renderPlainStringMatchesItself() {
        let attr = IRCFormatter.render("hello")
        #expect(String(attr.characters) == "hello")
    }

    @Test func renderStringEqualsStripCodes() {
        // Master invariant: the AttributedString's character stream is the
        // same as `stripCodes(raw)`. Anything that violates this breaks
        // overlay highlight ranges + URL detection alignment.
        let cases = [
            "plain text",
            "\(bold)bold\(bold) end",
            "\(color)04red\(reset) plain",
            "\(color)04,12fg+bg\(reset)",
            "\(hexCol)abcdefhexed\(reset)",
            "no end format \(bold)dangling",
            "Hello, world",                       // comma test
            "\(color)4Hello\(reset), world",      // comma after color
            ""
        ]
        for raw in cases {
            let attr = IRCFormatter.render(raw)
            let stripped = IRCFormatter.stripCodes(raw)
            #expect(String(attr.characters) == stripped, "case: \(raw.debugDescription)")
        }
    }

    // MARK: - renderWithLinks

    @Test func linkDetectionFindsHttpURLs() {
        let raw = "see https://example.com please"
        let attr = IRCFormatter.renderWithLinks(raw)
        // Walk runs and assert at least one has a non-nil link attribute.
        var hadLink = false
        for run in attr.runs {
            if run.attributes.link != nil { hadLink = true; break }
        }
        #expect(hadLink, "Expected link attribute on https://example.com")
    }

    @Test func linkDetectionWithMIRCCodes() {
        // Color codes mid-URL would break detection — but in practice
        // codes don't sit inside URLs. We just want detection to still
        // work when codes precede / follow the URL.
        let raw = "\(bold)visit\(bold) https://example.com today"
        let attr = IRCFormatter.renderWithLinks(raw)
        var found: URL?
        for run in attr.runs {
            if let u = run.attributes.link { found = u }
        }
        #expect(found?.absoluteString == "https://example.com")
    }

    @Test func plainTextProducesNoLinkAttribute() {
        let attr = IRCFormatter.renderWithLinks("nothing to see here")
        for run in attr.runs {
            #expect(run.attributes.link == nil)
        }
    }

    // MARK: - overlayHighlights

    @Test func overlayAppliesToMatchedRange() {
        let attr = IRCFormatter.render("hello world")
        let range = NSRange(location: 0, length: 5)         // "hello"
        let out = IRCFormatter.overlayHighlights(attr, ranges: [range], color: .red)
        // Iterate runs: at least one run inside the matched span should
        // carry our underline. That's a sufficient signal — the exact
        // foreground color depends on Color's NSColor backing on macOS.
        var hadUnderline = false
        for run in out.runs {
            if run.attributes.underlineStyle != nil { hadUnderline = true; break }
        }
        #expect(hadUnderline)
    }

    @Test func overlayWithEmptyRangesIsNoOp() {
        let original = IRCFormatter.render("hello")
        let out = IRCFormatter.overlayHighlights(original, ranges: [], color: .red)
        #expect(String(out.characters) == String(original.characters))
    }

    @Test func overlayBoundsCheckRejectsOverflow() {
        let attr = IRCFormatter.render("short")
        let bogus = NSRange(location: 0, length: 9999)
        // Should not crash, should leave the string unchanged.
        let out = IRCFormatter.overlayHighlights(attr, ranges: [bogus], color: .red)
        #expect(String(out.characters) == "short")
    }
}
