import Foundation
import SwiftUI
import Testing
@testable import Ircle

@MainActor
@Suite("Modern themes")
struct ModernThemeTests {

    @Test func shipsTwentyBuiltIns() {
        #expect(ModernTheme.all.count == 20)
        // All built-ins are flagged and have unique ids.
        #expect(ModernTheme.all.allSatisfy { $0.isBuiltIn })
        #expect(Set(ModernTheme.all.map(\.id)).count == 20)
    }

    @Test func everyBuiltInHasParseableColours() {
        // A bad hex literal would silently fall back; assert each colour parses.
        for t in ModernTheme.all {
            let hexes = [t.windowBG, t.paneBG, t.textBG, t.bevelLight, t.bevelDark,
                         t.hairline, t.chromeText, t.selection, t.normalText, t.timestamp,
                         t.serverText, t.topicText, t.joinText, t.partText, t.noticeText,
                         t.actionText, t.errorText, t.ownNick, t.otherNick, t.mentionBG]
            for h in hexes {
                #expect(Color(ircleHex: h) != nil, "theme \(t.id) has bad hex \(h)")
            }
        }
    }

    @Test func defaultThemeExists() {
        #expect(ModernTheme.named(ModernTheme.defaultID) != nil)
    }

    @Test func paletteMaterialisesColoursAndLuminance() {
        let t = ModernTheme.named("midnight")!
        let p = t.palette(baseFontSize: 13)
        #expect(p.isModern)
        #expect(p.flatChrome)                       // midnight is a flat theme
        #expect(p.normalText.ircleHexString == t.normalText)
        #expect(p.textBG.ircleHexString == t.textBG)
        // Luminance is derived from the (dark) background.
        #expect(p.messageBackgroundLuminance < 0.3)
    }

    @Test func beveledThemeKeepsBevels() {
        let p = ModernTheme.named("platinumPlus")!.palette()
        #expect(p.flatChrome == false)
    }

    @Test func fontFamiliesFlowIntoPalette() {
        // A flat modern theme defaults to Menlo body + system UI chrome.
        let p = ModernTheme.named("nord")!.palette(baseFontSize: 14)
        #expect(p.messageFontName == "Menlo")
        #expect(p.chromeFontName == "system-proportional")
        // Body size seeds from the global base size.
        #expect(p.resolvedFonts[.messageBody]?.size == 14)
        // A nostalgic beveled theme keeps the classic fonts.
        let noir = ModernTheme.named("noir")!.palette()
        #expect(noir.messageFontName == "Monaco")
        #expect(noir.chromeFontName == "Geneva")
    }

    @Test func resolvePrefersBuiltInThenUserThenFallback() {
        let custom = ModernTheme.duplicate(of: ModernTheme.named("dracula")!, name: "Mine")
        // Built-in id wins.
        #expect(ModernTheme.resolve(id: "dracula", userThemes: [custom]).id == "dracula")
        // Custom UUID resolves to the user theme.
        #expect(ModernTheme.resolve(id: custom.id, userThemes: [custom]).name == "Mine")
        // Unknown id falls back to the default.
        #expect(ModernTheme.resolve(id: "no-such-theme", userThemes: []).id == ModernTheme.defaultID)
    }

    @Test func duplicateGetsFreshIdAndProvenance() {
        let base = ModernTheme.named("tokyoNight")!
        let copy = ModernTheme.duplicate(of: base, name: "My Tokyo")
        #expect(copy.id != base.id)
        #expect(UUID(uuidString: copy.id) != nil)   // a real UUID, not a slug
        #expect(copy.isBuiltIn == false)
        #expect(copy.basedOn == "tokyoNight")
        #expect(copy.name == "My Tokyo")
        // Colours carried over.
        #expect(copy.normalText == base.normalText)
    }

    @Test func roundTripsThroughJSON() throws {
        let t = ModernTheme.duplicate(of: ModernTheme.named("sepia")!, name: "Reader")
        let data = try JSONEncoder().encode(t)
        let back = try JSONDecoder().decode(ModernTheme.self, from: data)
        #expect(back.id == t.id)
        #expect(back.name == "Reader")
        #expect(back.windowBG == t.windowBG)
        #expect(back.flatChrome == t.flatChrome)
    }

    @Test func decodeToleratesMissingFields() throws {
        // A theme authored by a future/newer version with only a couple of keys
        // must still decode (every missing field defaults) rather than throw.
        let sparse = ##"{"name":"Partial","textBG":"#101010"}"##
        let t = try JSONDecoder().decode(ModernTheme.self, from: Data(sparse.utf8))
        #expect(t.name == "Partial")
        #expect(t.textBG == "#101010")
        #expect(UUID(uuidString: t.id) != nil)       // a fresh id was minted
        #expect(Color(ircleHex: t.normalText) != nil) // defaulted field is valid
    }
}
