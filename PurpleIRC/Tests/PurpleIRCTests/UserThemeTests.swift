import Foundation
import SwiftUI
import Testing
@testable import PurpleIRC

@Suite("UserTheme + per-event color overrides")
@MainActor
struct UserThemeTests {

    // MARK: - duplicate(of:name:)

    @Test func duplicateCarriesEveryColorSlot() {
        let base = Theme.dracula
        let dup = UserTheme.duplicate(of: base, name: "My Dracula")

        // Name + basedOn metadata
        #expect(dup.name == "My Dracula")
        #expect(dup.basedOn == base.id)

        // Every hex slot must be set (non-empty) so the materialised
        // theme doesn't fall back to defaults for any slot — the
        // duplicate is supposed to be a full snapshot.
        #expect(!dup.chatBackgroundHex.isEmpty)
        #expect(!dup.chatForegroundHex.isEmpty)
        #expect(!dup.ownNickColorHex.isEmpty)
        #expect(!dup.infoColorHex.isEmpty)
        #expect(!dup.errorColorHex.isEmpty)
        #expect(!dup.motdColorHex.isEmpty)
        #expect(!dup.noticeColorHex.isEmpty)
        #expect(!dup.actionColorHex.isEmpty)
        #expect(!dup.joinColorHex.isEmpty)
        #expect(!dup.partColorHex.isEmpty)
        #expect(!dup.nickNickColorHex.isEmpty)
        #expect(!dup.mentionBackgroundHex.isEmpty)
        #expect(!dup.watchlistBackgroundHex.isEmpty)
        #expect(!dup.findBackgroundHex.isEmpty)
        #expect(dup.nickPaletteHex.count == base.nickPalette.count)
    }

    @Test func duplicateGivesEmptyNameASensibleFallback() {
        let dup = UserTheme.duplicate(of: Theme.classic, name: "")
        #expect(dup.name.contains("Classic"))
    }

    @Test func duplicateProducesFreshUUID() {
        let a = UserTheme.duplicate(of: Theme.midnight, name: "A")
        let b = UserTheme.duplicate(of: Theme.midnight, name: "B")
        #expect(a.id != b.id)
    }

    // MARK: - materialised

    @Test func materialisedRoundTripsCoreSlots() {
        let dup = UserTheme.duplicate(of: Theme.solarizedDark, name: "Sol")
        let live = dup.materialised
        // ID matches the user theme uuid (not the source built-in).
        #expect(live.id == dup.id.uuidString)
        // displayName matches the user-supplied name.
        #expect(live.displayName == dup.name)
        // Palette padded/truncated to exactly 8.
        #expect(live.nickPalette.count == 8)
    }

    @Test func materialisedTolerantOfMissingPaletteSlots() {
        var dup = UserTheme.duplicate(of: Theme.lavender, name: "Lav")
        dup.nickPaletteHex = ["#FF0000", "#00FF00"]   // only 2
        let live = dup.materialised
        #expect(live.nickPalette.count == 8) // padded to 8
    }

    @Test func materialisedTrucatesOversizedPalette() {
        var dup = UserTheme.duplicate(of: Theme.lavender, name: "Lav")
        dup.nickPaletteHex = Array(repeating: "#888888", count: 12)
        let live = dup.materialised
        #expect(live.nickPalette.count == 8) // truncated to 8
    }

    @Test func materialisedFallsBackOnGarbageHex() {
        var dup = UserTheme.duplicate(of: Theme.classic, name: "Garbage")
        dup.chatBackgroundHex = "not a color"
        dup.errorColorHex = ""
        // Materialise should NOT throw — the fallback values keep
        // rendering working even when the user typed nonsense.
        _ = dup.materialised
    }

    // MARK: - kindOverridesMaterialised

    @Test func kindOverridesParseGoodHexAndDropBad() {
        var dup = UserTheme.duplicate(of: Theme.midnight, name: "Mid")
        dup.kindOverrideHex = [
            "join":     "#00FF00",      // valid
            "part":     "#FFAA00",      // valid
            "garbage":  "#000000",      // unknown tag
            "error":    "not-a-hex",    // bad value
            "":         "#FFFFFF",      // empty key
        ]
        let map = dup.kindOverridesMaterialised
        #expect(map[.join] != nil)
        #expect(map[.part] != nil)
        #expect(map[.error] == nil)         // bad hex dropped
        #expect(map.count == 2)             // only 2 valid entries
    }

    @Test func emptyKindOverridesProducesEmptyMap() {
        let dup = UserTheme.duplicate(of: Theme.classic, name: "Plain")
        #expect(dup.kindOverridesMaterialised.isEmpty)
    }

    // MARK: - Theme.resolve(id:userThemes:)

    @Test func resolveBuiltInWinsOnIDCollision() {
        // Forge a UserTheme whose uuid string equals a built-in id.
        // Built-ins should still win — we don't let user themes
        // shadow named built-ins by accident.
        var dup = UserTheme.duplicate(of: Theme.midnight, name: "Fake")
        dup = UserTheme(
            id: UUID(),
            name: "Fake",
            basedOn: nil,
            createdAt: dup.createdAt,
            chatBackgroundHex: dup.chatBackgroundHex,
            chatForegroundHex: dup.chatForegroundHex,
            ownNickColorHex: dup.ownNickColorHex,
            infoColorHex: dup.infoColorHex,
            errorColorHex: dup.errorColorHex,
            motdColorHex: dup.motdColorHex,
            noticeColorHex: dup.noticeColorHex,
            actionColorHex: dup.actionColorHex,
            joinColorHex: dup.joinColorHex,
            partColorHex: dup.partColorHex,
            nickNickColorHex: dup.nickNickColorHex,
            mentionBackgroundHex: dup.mentionBackgroundHex,
            watchlistBackgroundHex: dup.watchlistBackgroundHex,
            findBackgroundHex: dup.findBackgroundHex,
            nickPaletteHex: dup.nickPaletteHex
        )

        // Asking for "midnight" must always return the built-in.
        let resolved = Theme.resolve(id: "midnight", userThemes: [dup])
        #expect(resolved.id == "midnight")
        #expect(resolved.displayName == "Midnight")
    }

    @Test func resolveFindsUserThemeByUUID() {
        let dup = UserTheme.duplicate(of: Theme.lavender, name: "Custom")
        let resolved = Theme.resolve(id: dup.id.uuidString, userThemes: [dup])
        #expect(resolved.id == dup.id.uuidString)
        #expect(resolved.displayName == "Custom")
    }

    @Test func resolveFallsBackToClassicOnMiss() {
        let resolved = Theme.resolve(id: "no-such-theme", userThemes: [])
        #expect(resolved.id == "classic")
    }

    @Test func resolveWithEmptyIDFallsBackToClassic() {
        let resolved = Theme.resolve(id: "", userThemes: [])
        #expect(resolved.id == "classic")
    }

    // MARK: - Codable round-trip

    @Test func userThemeRoundTripsThroughJSON() throws {
        var original = UserTheme.duplicate(of: Theme.tokyoNight, name: "Tokyo")
        original.kindOverrideHex = ["join": "#00FF00", "error": "#FF00FF"]

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserTheme.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.basedOn == original.basedOn)
        #expect(decoded.chatBackgroundHex == original.chatBackgroundHex)
        #expect(decoded.kindOverrideHex == original.kindOverrideHex)
        #expect(decoded.nickPaletteHex == original.nickPaletteHex)
    }

    // MARK: - ChatLineKindTag stability

    @Test func kindTagRawValuesAreStableStrings() {
        // The on-disk format keys overrides by raw string. Renaming
        // these enum cases is fine; renaming the rawValues breaks
        // every existing user theme. Pinning the rawValues here
        // catches accidental renames.
        #expect(ChatLineKindTag.info.rawValue        == "info")
        #expect(ChatLineKindTag.error.rawValue       == "error")
        #expect(ChatLineKindTag.privmsg.rawValue     == "privmsg")
        #expect(ChatLineKindTag.privmsgSelf.rawValue == "privmsg.self")
        #expect(ChatLineKindTag.action.rawValue      == "action")
        #expect(ChatLineKindTag.notice.rawValue      == "notice")
        #expect(ChatLineKindTag.join.rawValue        == "join")
        #expect(ChatLineKindTag.part.rawValue        == "part")
        #expect(ChatLineKindTag.quit.rawValue        == "quit")
        #expect(ChatLineKindTag.nick.rawValue        == "nick")
        #expect(ChatLineKindTag.topic.rawValue       == "topic")
        #expect(ChatLineKindTag.raw.rawValue         == "raw")
        #expect(ChatLineKindTag.mention.rawValue     == "mention")
        #expect(ChatLineKindTag.watchlist.rawValue   == "watchlist")
    }
}
