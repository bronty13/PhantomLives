import Foundation
import SwiftUI
import Testing
@testable import PurpleIRC

@Suite("FontStyle inheritance + ResolvedFont")
struct FontStyleTests {

    // MARK: - Root resolution from legacy fields

    @Test func rootFromLegacySystemMonoMapsToToken() {
        let style = FontStyle()  // pure inherit
        let r = FontStyle.resolveChatBody(
            legacy: .systemMono,
            legacySize: 13,
            legacyBold: false,
            style: style
        )
        #expect(r.family == "system-mono")
        #expect(r.isBuiltInMonoToken)
        #expect(!r.isBuiltInPropToken)
        #expect(r.size == 13)
        #expect(r.weight == .regular)
        #expect(!r.italic)
        #expect(!r.ligaturesEnabled)
        #expect(r.tracking == 0)
        #expect(r.lineHeightMultiple == 1.0)
    }

    @Test func rootFromLegacyProportionalMapsToToken() {
        let r = FontStyle.resolveChatBody(
            legacy: .proportional, legacySize: 14, legacyBold: false,
            style: FontStyle()
        )
        #expect(r.family == "system-proportional")
        #expect(r.isBuiltInPropToken)
        #expect(!r.isBuiltInMonoToken)
    }

    @Test func rootFromLegacyMenloMapsToFamilyName() {
        let r = FontStyle.resolveChatBody(
            legacy: .menlo, legacySize: 12, legacyBold: false,
            style: FontStyle()
        )
        #expect(r.family == "Menlo")
        #expect(!r.isBuiltInMonoToken)
        #expect(!r.isBuiltInPropToken)
    }

    @Test func legacyBoldDrivesRootWeight() {
        let r = FontStyle.resolveChatBody(
            legacy: .menlo, legacySize: 12, legacyBold: true,
            style: FontStyle()
        )
        #expect(r.weight == .bold)
    }

    // MARK: - FontStyle overrides

    @Test func styleFamilyOverridesLegacyEnum() {
        var style = FontStyle()
        style.family = "Fira Code"
        let r = FontStyle.resolveChatBody(
            legacy: .systemMono, legacySize: 13, legacyBold: false,
            style: style
        )
        #expect(r.family == "Fira Code")
        #expect(!r.isBuiltInMonoToken)
    }

    @Test func styleSizeOverridesLegacySize() {
        var style = FontStyle()
        style.size = 18
        let r = FontStyle.resolveChatBody(
            legacy: .menlo, legacySize: 13, legacyBold: false,
            style: style
        )
        #expect(r.size == 18)
    }

    @Test func zeroStyleSizeInheritsFromLegacy() {
        var style = FontStyle()
        style.size = 0   // explicit "inherit" sentinel
        let r = FontStyle.resolveChatBody(
            legacy: .menlo, legacySize: 13, legacyBold: false,
            style: style
        )
        #expect(r.size == 13)
    }

    @Test func styleWeightOverridesLegacyBold() {
        var style = FontStyle()
        style.weight = .light
        let r = FontStyle.resolveChatBody(
            legacy: .menlo, legacySize: 13, legacyBold: true,
            style: style
        )
        // The explicit .light weight wins over the legacyBold input.
        #expect(r.weight == .light)
    }

    @Test func inheritWeightFallsBackToLegacy() {
        var style = FontStyle()
        style.weight = .inherit
        let r = FontStyle.resolveChatBody(
            legacy: .menlo, legacySize: 13, legacyBold: true,
            style: style
        )
        #expect(r.weight == .bold)  // came from legacyBold
    }

    @Test func styleLigaturesOverrideLegacyDefault() {
        var style = FontStyle()
        style.ligatures = true
        let r = FontStyle.resolveChatBody(
            legacy: .systemMono, legacySize: 13, legacyBold: false,
            style: style
        )
        #expect(r.ligaturesEnabled)
    }

    @Test func styleTrackingFlowsThrough() {
        var style = FontStyle()
        style.tracking = 1.5
        let r = FontStyle.resolveChatBody(
            legacy: .systemMono, legacySize: 13, legacyBold: false,
            style: style
        )
        #expect(r.tracking == 1.5)
    }

    @Test func styleLineHeightFlowsThrough() {
        var style = FontStyle()
        style.lineHeightMultiple = 1.4
        let r = FontStyle.resolveChatBody(
            legacy: .systemMono, legacySize: 13, legacyBold: false,
            style: style
        )
        #expect(r.lineHeightMultiple == 1.4)
    }

    // MARK: - Slot inheritance from chat body

    @Test func emptySlotInheritsEverythingFromParent() {
        let parent = FontStyle.resolveChatBody(
            legacy: .menlo, legacySize: 14, legacyBold: true,
            style: FontStyle()
        )
        let slotResolved = FontStyle().resolved(parent: parent)
        #expect(slotResolved.family == parent.family)
        #expect(slotResolved.size == parent.size)
        #expect(slotResolved.weight == parent.weight)
        #expect(slotResolved.italic == parent.italic)
        #expect(slotResolved.tracking == parent.tracking)
        #expect(slotResolved.lineHeightMultiple == parent.lineHeightMultiple)
        #expect(slotResolved.ligaturesEnabled == parent.ligaturesEnabled)
    }

    @Test func slotPartialOverrideOnlyChangesSetFields() {
        let parent = FontStyle.resolveChatBody(
            legacy: .menlo, legacySize: 14, legacyBold: false,
            style: FontStyle()
        )
        var slot = FontStyle()
        slot.family = "Iosevka"
        slot.italic = true
        let r = slot.resolved(parent: parent)
        #expect(r.family == "Iosevka")          // overridden
        #expect(r.italic)                        // overridden
        #expect(r.size == parent.size)           // inherited
        #expect(r.weight == parent.weight)       // inherited
        #expect(r.tracking == parent.tracking)   // inherited
    }

    // MARK: - Codable

    @Test func fontStyleRoundTripsThroughJSON() throws {
        var style = FontStyle()
        style.family = "JetBrains Mono"
        style.size = 14
        style.weight = .semibold
        style.italic = true
        style.ligatures = true
        style.tracking = 0.5
        style.lineHeightMultiple = 1.2

        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(FontStyle.self, from: data)

        #expect(decoded == style)
    }

    @Test func emptyFontStyleRoundTripsToEmpty() throws {
        let style = FontStyle()
        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(FontStyle.self, from: data)
        #expect(decoded == FontStyle.inherit)
    }

    // MARK: - Weight raw values are stable

    @Test func weightRawValuesAreStableStrings() {
        // The on-disk representation persists weight by rawValue.
        // Renaming a case is fine; renaming the rawValue breaks
        // every saved per-element font.
        #expect(FontStyle.Weight.inherit.rawValue    == "inherit")
        #expect(FontStyle.Weight.regular.rawValue    == "regular")
        #expect(FontStyle.Weight.semibold.rawValue   == "semibold")
        #expect(FontStyle.Weight.bold.rawValue       == "bold")
        #expect(FontStyle.Weight.heavy.rawValue      == "heavy")
        #expect(FontStyle.Weight.black.rawValue      == "black")
    }
}
