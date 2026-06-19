import Foundation
import SwiftUI
import Testing
@testable import Ircle

@MainActor
@Suite("Custom colours")
struct ThemeColorTests {

    @Test func hexParsesAndRoundTrips() {
        #expect(Color(ircleHex: "#1A2B3C")?.ircleHexString == "#1A2B3C")
        #expect(Color(ircleHex: "FF0000")?.ircleHexString == "#FF0000")   // no '#' ok
        #expect(Color(ircleHex: "") == nil)
        #expect(Color(ircleHex: "nope") == nil)
        #expect(Color(ircleHex: "12345") == nil)                          // wrong length
    }

    @Test func applyingOverridesTextAndBackground() {
        let p = PlatinumPalette.platinum().applying(textHex: "#FF0000", backgroundHex: "#000000")
        #expect(p.normalText.ircleHexString == "#FF0000")
        #expect(p.textBG.ircleHexString == "#000000")
        #expect(p.messageBackgroundLuminance < 0.05)   // black bg → ~0 (drives mIRC contrast)
    }

    @Test func emptyOverridesKeepTheTheme() {
        let base = PlatinumPalette.platinum()
        let p = base.applying(textHex: "", backgroundHex: "")
        #expect(p.normalText.ircleHexString == base.normalText.ircleHexString)
        #expect(p.messageBackgroundLuminance == base.messageBackgroundLuminance)
    }

    @Test func customColorHexesPersist() throws {
        var s = AppSettings()
        #expect(s.customTextColorHex.isEmpty && s.customBackgroundColorHex.isEmpty)
        s.customTextColorHex = "#112233"
        s.customBackgroundColorHex = "#445566"
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(back.customTextColorHex == "#112233")
        #expect(back.customBackgroundColorHex == "#445566")
    }
}
