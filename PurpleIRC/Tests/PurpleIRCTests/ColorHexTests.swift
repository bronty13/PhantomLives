import Foundation
import SwiftUI
import Testing
@testable import PurpleIRC

/// `Color` hex (de)serialization. `hexARGB` preserves opacity for theme
/// slots that use translucency; `hexRGB` deliberately drops it.
@MainActor
@Suite("Color hex")
struct ColorHexTests {

    @Test func argbRoundTripsAlpha() {
        let c = Color(hex: "#80FF0000")   // ~50% red
        #expect(c != nil)
        #expect(c?.hexARGB == "#80FF0000")
    }

    @Test func argbKeepsFullyOpaque() {
        let c = Color(hex: "#FF00FF00")
        #expect(c?.hexARGB == "#FF00FF00")
    }

    @Test func rgbDropsAlpha() {
        // hexRGB intentionally flattens opacity — this is the behaviour the
        // theme builder switched away from for translucent slots.
        let c = Color(hex: "#3300FF00")
        #expect(c?.hexRGB == "#00FF00")
    }

    @Test func parsesSixAndEightDigit() {
        #expect(Color(hex: "#112233") != nil)
        #expect(Color(hex: "44112233") != nil)
        #expect(Color(hex: "nope") == nil)
    }
}
