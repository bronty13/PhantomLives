import XCTest
import SwiftUI
@testable import PurpleDiary

/// Locks down the built-in theme table and the derive-by-match selection logic.
/// The selection model (no stored theme id; the selected theme is whichever
/// `(accentHex, scheme)` pair matches the persisted settings) only works if
/// every theme's pair is unique and every accent hex is a valid color — so those
/// invariants are asserted here rather than discovered at runtime.
final class ThemeTests: XCTestCase {

    func testThereAreFifteenThemes() {
        XCTAssertEqual(Theme.all.count, 15)
    }

    func testThemeIdsAreUnique() {
        let ids = Theme.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "theme ids must be unique")
    }

    func testAccentSchemePairsAreUnique() {
        // Selection is derived by matching (accentHex, scheme); duplicates would
        // make `Theme.matching` ambiguous and the picker highlight wrong.
        let pairs = Theme.all.map { "\($0.accentHex.lowercased())|\($0.scheme)" }
        XCTAssertEqual(Set(pairs).count, pairs.count, "(accent, scheme) pairs must be unique")
    }

    func testEveryAccentHexIsValid() {
        for theme in Theme.all {
            XCTAssertNotNil(Color(hex: theme.accentHex), "theme \(theme.id) has an invalid accent hex \(theme.accentHex)")
        }
    }

    func testEverySchemeIsLightOrDark() {
        for theme in Theme.all {
            XCTAssertTrue(theme.scheme == "light" || theme.scheme == "dark",
                          "theme \(theme.id) scheme must be light/dark, got \(theme.scheme)")
        }
    }

    func testSignatureIsPurpleDarkAndExists() {
        XCTAssertEqual(Theme.signatureId, "purple-dark")
        XCTAssertEqual(Theme.signature.id, "purple-dark")
        XCTAssertTrue(Theme.signature.isDark)
        XCTAssertEqual(Theme.signature.accentHex, "#7C5CFF")
    }

    func testBothPurpleThemesPresentAndDistinguishedByScheme() {
        guard let dark = Theme.byId("purple-dark"), let light = Theme.byId("purple-light") else {
            return XCTFail("both purple themes must exist")
        }
        XCTAssertEqual(dark.accentHex, light.accentHex, "the two purples share an accent")
        XCTAssertNotEqual(dark.scheme, light.scheme, "they differ only by scheme")
    }

    func testMatchingRoundTripsForEveryTheme() {
        for theme in Theme.all {
            let match = Theme.matching(accentHex: theme.accentHex, colorScheme: theme.scheme)
            XCTAssertEqual(match?.id, theme.id, "matching should round-trip theme \(theme.id)")
        }
    }

    func testMatchingIsCaseInsensitiveOnHex() {
        // The system ColorPicker can persist a lowercased hex; it should still
        // resolve to the same theme.
        let match = Theme.matching(accentHex: "#7c5cff", colorScheme: "dark")
        XCTAssertEqual(match?.id, "purple-dark")
    }

    func testMatchingReturnsNilForCustomAccentOrAutoMode() {
        XCTAssertNil(Theme.matching(accentHex: "#123456", colorScheme: "dark"),
                     "an accent no theme uses is Custom")
        XCTAssertNil(Theme.matching(accentHex: "#7C5CFF", colorScheme: "auto"),
                     "match-system mode is Custom even with a theme's accent")
    }

    // `AppState.applyTheme` / `selectedTheme` are thin wrappers: applyTheme
    // writes (accentHex, scheme) into settings, selectedTheme reads them back
    // through `Theme.matching`. We exercise that exact data path at the
    // AppSettings level — constructing a full `AppState` in a test would build
    // the DB singleton and run a launch backup against the real ~/Downloads,
    // which the rest of the suite deliberately avoids.

    func testWritingAThemesFieldsIntoSettingsSelectsIt() {
        var s = AppSettings()
        let ocean = Theme.byId("ocean")!
        s.accentColorHex = ocean.accentHex
        s.colorScheme = ocean.scheme
        XCTAssertEqual(Theme.matching(accentHex: s.accentColorHex, colorScheme: s.colorScheme)?.id, "ocean")

        let rose = Theme.byId("rose")!
        s.accentColorHex = rose.accentHex
        s.colorScheme = rose.scheme
        XCTAssertEqual(s.colorScheme, "light")
        XCTAssertEqual(Theme.matching(accentHex: s.accentColorHex, colorScheme: s.colorScheme)?.id, "rose")
    }

    func testCustomAccentReadsAsNoSelectedTheme() {
        var s = AppSettings()
        s.accentColorHex = "#0A0B0C"   // a color no theme uses
        XCTAssertNil(Theme.matching(accentHex: s.accentColorHex, colorScheme: s.colorScheme),
                     "a custom accent should read as Custom (no selected theme)")
    }

    func testFreshInstallDefaultsToSignatureTheme() {
        // The AppSettings defaults (accent #7C5CFF + dark) must resolve to the
        // signature theme, so a brand-new install opens on Purple Dark.
        let s = AppSettings()
        XCTAssertEqual(Theme.matching(accentHex: s.accentColorHex, colorScheme: s.colorScheme)?.id,
                       Theme.signatureId)
    }
}
