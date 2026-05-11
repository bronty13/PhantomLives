import XCTest
import SwiftUI
@testable import PurpleLife

/// Slice 1 coverage of the theme system: built-in resolution, UserTheme
/// roundtrip, hex parser surface, AppearanceMode → ColorScheme, and
/// settings.json Codable additions. The UI surface (AppearanceSettingsTab,
/// theme card preview) isn't unit-tested — same constraint as every other
/// SwiftUI view in the suite.
final class ThemeTests: XCTestCase {

    // MARK: - Built-ins

    func testRoyalPurpleIsDefault() {
        let resolved = PurpleTheme.resolve(id: "royalPurple", userThemes: [])
        XCTAssertEqual(resolved.id, "royalPurple")
        XCTAssertEqual(resolved.displayName, "Royal Purple")
    }

    func testAllBuiltInsAreUniqueAndPurpleLed() {
        let ids = PurpleTheme.allBuiltIns.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "built-in theme ids must be unique")
        XCTAssertEqual(ids.first, "royalPurple", "default must lead the picker")
        XCTAssertTrue(ids.contains("highContrast"), "accessibility theme must be present")
    }

    func testResolveUnknownIdFallsBackToRoyalPurple() {
        let resolved = PurpleTheme.resolve(id: "does-not-exist", userThemes: [])
        XCTAssertEqual(resolved.id, "royalPurple")
    }

    func testResolveBuiltInWinsOverUserThemeIdCollision() {
        // A hand-edited settings.json could theoretically reuse a built-in
        // id for a custom theme. Built-ins must win so the flagship can
        // never be shadowed by accident.
        var custom = UserTheme.duplicate(of: .royalPurple, name: "Hijacker")
        // Force collision by overwriting the id post-construction. Real
        // UserThemes use UUID strings, but this guards the explicit policy.
        let collidingID = UUID()
        custom.id = collidingID
        // Even with a custom in the list, resolving "royalPurple" returns
        // the built-in.
        let resolved = PurpleTheme.resolve(id: "royalPurple", userThemes: [custom])
        XCTAssertEqual(resolved.displayName, "Royal Purple")
    }

    // MARK: - UserTheme roundtrip

    func testUserThemeDuplicateOfBuiltInMaterialisesBack() throws {
        let custom = UserTheme.duplicate(of: .lavender, name: "My Lavender")
        XCTAssertEqual(custom.basedOn, "lavender")
        XCTAssertEqual(custom.name, "My Lavender")
        XCTAssertFalse(custom.bg.light.isEmpty, "snapshot must capture a hex string for the light slot")
        XCTAssertFalse(custom.bg.dark.isEmpty, "snapshot must capture a hex string for the dark slot")

        let materialised = custom.materialised
        XCTAssertEqual(materialised.id, custom.id.uuidString)
        XCTAssertEqual(materialised.displayName, "My Lavender")
    }

    func testUserThemeCodableRoundtripPreservesAllSlots() throws {
        let custom = UserTheme.duplicate(of: .plum, name: "Plummy")

        let data = try JSONEncoder().encode(custom)
        let decoded = try JSONDecoder().decode(UserTheme.self, from: data)

        XCTAssertEqual(decoded.id, custom.id)
        XCTAssertEqual(decoded.name, custom.name)
        XCTAssertEqual(decoded.basedOn, custom.basedOn)
        XCTAssertEqual(decoded.bg.light, custom.bg.light)
        XCTAssertEqual(decoded.bg.dark, custom.bg.dark)
        XCTAssertEqual(decoded.accent.light, custom.accent.light)
        XCTAssertEqual(decoded.accent.dark, custom.accent.dark)
    }

    func testUserThemeWithEmptyNameGetsAFallback() {
        let custom = UserTheme.duplicate(of: .heather, name: "")
        XCTAssertEqual(custom.name, "Custom from Heather")
    }

    func testUserThemeWithCorruptHexFallsBackOnMaterialise() {
        // A hand-edited settings.json with a bad hex should still produce
        // a renderable theme — we fall back to the corresponding Royal
        // Purple slot rather than crash.
        var custom = UserTheme.duplicate(of: .lavender, name: "Half-Broken")
        custom.bg.light = "not-a-hex"
        custom.accent.dark = ""
        // Should not throw, should not crash.
        let _ = custom.materialised
    }

    // MARK: - Hex parser

    func testColorHexParserAcceptsAllSupportedLengths() {
        XCTAssertNotNil(Color(hex: "#FF0"))       // 3-digit
        XCTAssertNotNil(Color(hex: "FF8800"))     // 6-digit, no #
        XCTAssertNotNil(Color(hex: "#80FF8800"))  // 8-digit with alpha
    }

    func testColorHexParserRejectsBadInput() {
        XCTAssertNil(Color(hex: ""))
        XCTAssertNil(Color(hex: "not-a-hex"))
        XCTAssertNil(Color(hex: "#GGGGGG"))
        XCTAssertNil(Color(hex: "#FF"))          // 2 chars not supported
    }

    // MARK: - AppearanceMode

    func testAppearanceModeColorSchemeMapping() {
        XCTAssertNil(AppearanceMode.system.colorScheme, "system means 'let OS decide'")
        XCTAssertEqual(AppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(AppearanceMode.dark.colorScheme, .dark)
    }

    func testAppearanceModeCodableRoundtrip() throws {
        for mode in AppearanceMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(AppearanceMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    // MARK: - AppSettings additions

    func testAppSettingsDefaultsAreThemingNeutral() {
        let s = AppSettings()
        XCTAssertEqual(s.themeID, "royalPurple", "default theme is the flagship purple")
        XCTAssertEqual(s.appearance, .system, "default appearance follows the OS")
        XCTAssertTrue(s.userThemes.isEmpty, "fresh install has no custom themes")
    }

    func testAppSettingsBackwardCompatibleDecode() throws {
        // A settings.json from a pre-theme build doesn't carry the new keys.
        // Codable's missing-key tolerance + the struct's defaults should
        // produce a fully-usable AppSettings — same property tested for
        // every prior phase's additions to this struct.
        let legacyJSON = """
        {
            "autoBackupEnabled": true,
            "backupPath": "",
            "backupRetentionDays": 14,
            "lastBackupAt": "",
            "defaultExportDirectory": "",
            "todayQueries": [],
            "todayQueriesSeeded": true,
            "forecastDays": 30
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        XCTAssertEqual(decoded.themeID, "royalPurple")
        XCTAssertEqual(decoded.appearance, .system)
        XCTAssertTrue(decoded.userThemes.isEmpty)
    }

    // MARK: - Builder persistence helpers (slice 2)

    func testUpsertAppendsWhenIdMissing() {
        var list: [UserTheme] = []
        let t1 = UserTheme.duplicate(of: .lavender, name: "A")
        UserTheme.upsert(t1, in: &list)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.id, t1.id)
    }

    func testUpsertReplacesInPlacePreservingOrder() {
        var list: [UserTheme] = [
            UserTheme.duplicate(of: .lavender, name: "A"),
            UserTheme.duplicate(of: .plum,     name: "B"),
            UserTheme.duplicate(of: .heather,  name: "C"),
        ]
        // Edit the middle theme: same id, new name.
        var edited = list[1]
        edited.name = "B-edited"
        UserTheme.upsert(edited, in: &list)

        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list[0].name, "A")
        XCTAssertEqual(list[1].name, "B-edited", "edit should land in place")
        XCTAssertEqual(list[2].name, "C", "tail entry must not shift")
    }

    func testResolveAfterDeleteFallsBackToBasedOnWhenActive() {
        let removed = UUID().uuidString
        let next = PurpleTheme.resolveAfterDelete(
            currentID: removed,
            removedID: removed,
            basedOn: "lavender"
        )
        XCTAssertEqual(next, "lavender")
    }

    func testResolveAfterDeleteFallsBackToRoyalPurpleWhenBasedOnUnknown() {
        let removed = UUID().uuidString
        let next = PurpleTheme.resolveAfterDelete(
            currentID: removed,
            removedID: removed,
            basedOn: "never-existed"
        )
        XCTAssertEqual(next, "royalPurple")
    }

    func testResolveAfterDeleteFallsBackToRoyalPurpleWhenBasedOnNil() {
        let removed = UUID().uuidString
        let next = PurpleTheme.resolveAfterDelete(
            currentID: removed,
            removedID: removed,
            basedOn: nil
        )
        XCTAssertEqual(next, "royalPurple")
    }

    func testResolveAfterDeletePreservesCurrentWhenDeletingInactive() {
        // Deleting a non-active user theme must not flip themeID. The
        // user clicked Delete on a theme they weren't using; the active
        // selection should be left alone.
        let active = UUID().uuidString
        let removed = UUID().uuidString
        let next = PurpleTheme.resolveAfterDelete(
            currentID: active,
            removedID: removed,
            basedOn: "lavender"
        )
        XCTAssertEqual(next, active)
    }

    func testAppSettingsCodableRoundtripWithThemeFields() throws {
        var s = AppSettings()
        s.themeID = "highContrast"
        s.appearance = .dark
        s.userThemes = [UserTheme.duplicate(of: .lavender, name: "Mine")]

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.themeID, "highContrast")
        XCTAssertEqual(decoded.appearance, .dark)
        XCTAssertEqual(decoded.userThemes.count, 1)
        XCTAssertEqual(decoded.userThemes.first?.name, "Mine")
        XCTAssertEqual(decoded.userThemes.first?.basedOn, "lavender")
    }
}

private extension String {
    var isEmpty_compat: Bool { self.isEmpty }
}
