import Foundation
import SwiftUI
import Testing
@testable import Ircle

@Suite("MircRenderer")
struct MircRendererTests {

    /// The visible characters of a rendered run must equal the code-stripped
    /// text — i.e. every control byte is consumed, never printed.
    @Test func visibleTextMatchesStrippedText() {
        let raw = "\u{02}bold\u{02} \u{03}04red\u{03} \u{1D}it\u{1D}"
        let attr = MircRenderer.attributed(raw, size: 12, baseColor: .black)
        #expect(String(attr.characters) == "bold red it")
    }

    @Test func plainTextIsOneBaseColoredRun() {
        let attr = MircRenderer.attributed("hello", size: 12, baseColor: .black)
        #expect(String(attr.characters) == "hello")
        let colors = attr.runs.map { $0.foregroundColor }
        #expect(colors.allSatisfy { $0 == .black })
    }

    @Test func colorCodeSetsForegroundOnThatRun() {
        // ^C04 = mIRC red (1,0,0).
        let attr = MircRenderer.attributed("\u{03}04danger", size: 12, baseColor: .black)
        let redRun = attr.runs.first { String(attr[$0.range].characters) == "danger" }
        #expect(redRun?.foregroundColor == Color(red: 1, green: 0, blue: 0))
    }

    @Test func colorResetReturnsToBase() {
        // text before code = base; ^C04 colored; ^C (bare) resets to base.
        let attr = MircRenderer.attributed("a\u{03}04b\u{03}c", size: 12, baseColor: .black)
        #expect(String(attr.characters) == "abc")
        // first run "a" base, middle "b" red, last "c" base again.
        var seen: [(String, Color?)] = []
        for run in attr.runs { seen.append((String(attr[run.range].characters), run.foregroundColor)) }
        #expect(seen.first?.1 == .black)
        #expect(seen.last?.1 == .black)
        #expect(seen.contains { $0.0.contains("b") && $0.1 == Color(red: 1, green: 0, blue: 0) })
    }

    @Test func foregroundBackgroundColorPair() {
        // ^C00,01 = white on black.
        let attr = MircRenderer.attributed("\u{03}00,01x", size: 12, baseColor: .gray)
        let run = attr.runs.first { String(attr[$0.range].characters) == "x" }
        #expect(run?.foregroundColor == Color(red: 1, green: 1, blue: 1))
        #expect(run?.backgroundColor == Color(red: 0, green: 0, blue: 0))
    }

    @Test func hexColorIsParsed() {
        let attr = MircRenderer.attributed("\u{04}FF0000hot", size: 12, baseColor: .black)
        let run = attr.runs.first { String(attr[$0.range].characters) == "hot" }
        #expect(run?.foregroundColor == Color(red: 1, green: 0, blue: 0))
    }

    @Test func incompleteHexLeavesDigitsAsText() {
        // Fewer than 6 hex digits → not a color; the ^D byte is dropped, the
        // partial run stays literal text.
        let attr = MircRenderer.attributed("\u{04}FF00xy", size: 12, baseColor: .black)
        #expect(String(attr.characters) == "FF00xy")
    }

    @Test func plainHelperProducesRequestedColor() {
        let attr = MircRenderer.plain("<bob> ", size: 12, color: Color(red: 0.3, green: 0.2, blue: 0))
        #expect(String(attr.characters) == "<bob> ")
        #expect(attr.runs.first?.foregroundColor == Color(red: 0.3, green: 0.2, blue: 0))
    }
}
