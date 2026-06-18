import Foundation
import Testing
@testable import IRCKit

@Suite("IRCText.stripFormatting")
struct IRCTextTests {

    @Test func plainTextPassesThrough() {
        #expect(IRCText.stripFormatting("hello world") == "hello world")
        #expect(IRCText.stripFormatting("") == "")
    }

    @Test func stripsSimpleControlBytes() {
        // bold, italic, underline, strike, reverse, reset, mono
        #expect(IRCText.stripFormatting("\u{02}bold\u{02}") == "bold")
        #expect(IRCText.stripFormatting("\u{1D}it\u{1D}") == "it")
        #expect(IRCText.stripFormatting("\u{1F}u\u{1F}") == "u")
        #expect(IRCText.stripFormatting("\u{1E}s\u{1E}") == "s")
        #expect(IRCText.stripFormatting("\u{16}rev\u{16}") == "rev")
        #expect(IRCText.stripFormatting("a\u{0F}b") == "ab")
        #expect(IRCText.stripFormatting("a\u{11}b") == "ab")
    }

    @Test func stripsColorRunWithForegroundOnly() {
        // ^C04red → "red" (two-digit code consumed)
        #expect(IRCText.stripFormatting("\u{03}04red") == "red")
        // single-digit code
        #expect(IRCText.stripFormatting("\u{03}4red") == "red")
    }

    @Test func stripsColorRunWithForegroundAndBackground() {
        // ^C04,08text → "text"
        #expect(IRCText.stripFormatting("\u{03}04,08text") == "text")
        // single-digit fg + bg
        #expect(IRCText.stripFormatting("\u{03}4,8text") == "text")
    }

    @Test func bareColorResetIsStripped() {
        // ^C with no digits resets color; the byte alone is removed.
        #expect(IRCText.stripFormatting("a\u{03}b") == "ab")
    }

    @Test func commaNotPartOfColorIsPreserved() {
        // After a 2-digit fg with no bg digits, a following comma+text is
        // literal — only digits are consumed as the bg code.
        #expect(IRCText.stripFormatting("\u{03}04,text") == ",text")
    }

    @Test func stripsHexColorRun() {
        // ^D + 6 hex fg
        #expect(IRCText.stripFormatting("\u{04}FF0000red") == "red")
        // ^D + fg,bg
        #expect(IRCText.stripFormatting("\u{04}FF0000,00FF00text") == "text")
    }

    @Test func incompleteHexColorLeavesDigitsIntact() {
        // Fewer than 6 hex digits: consumeHex returns to start, so the
        // partial run stays as literal text (only the ^D byte is dropped).
        #expect(IRCText.stripFormatting("\u{04}FF00xx") == "FF00xx")
    }

    @Test func mixedFormattingYieldsCleanPlainText() {
        let raw = "\u{02}\u{03}04Hello\u{03}, \u{1D}world\u{1D}!\u{0F}"
        #expect(IRCText.stripFormatting(raw) == "Hello, world!")
    }
}
