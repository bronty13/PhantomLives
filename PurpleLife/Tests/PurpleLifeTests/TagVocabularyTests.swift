import XCTest
@testable import PurpleLife

/// Increment 1 tag-storage tests at the model + AppSettings layer.
/// Verifies `TagDef` round-trips, `AppSettings.tagVocabulary` carries
/// through encode/decode, and the lenient decoder accepts a legacy
/// settings.json that pre-dates the tag vocabulary.
final class TagVocabularyTests: XCTestCase {

    func testTagDefCodableRoundTrip() throws {
        let tag = TagDef.make(name: "urgent", colorHex: "#FF8800")
        let data = try JSONEncoder().encode(tag)
        let decoded = try JSONDecoder().decode(TagDef.self, from: data)
        XCTAssertEqual(decoded, tag, "TagDef should round-trip through JSON unchanged")
    }

    func testTagDefMakeStampsTimestamps() {
        let tag = TagDef.make(name: "later")
        XCTAssertFalse(tag.id.isEmpty)
        XCTAssertFalse(tag.createdAt.isEmpty)
        XCTAssertFalse(tag.updatedAt.isEmpty)
        XCTAssertNil(tag.colorHex, "Color is optional and defaults to nil")
        XCTAssertEqual(tag.name, "later")
    }

    func testAppSettingsRoundTripsTagVocabulary() throws {
        var settings = AppSettings()
        settings.tagVocabulary = [
            TagDef.make(name: "ideas",   colorHex: "#5A4FCF"),
            TagDef.make(name: "reading", colorHex: nil)
        ]
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.tagVocabulary.count, 2)
        XCTAssertEqual(decoded.tagVocabulary.map(\.name), ["ideas", "reading"])
        XCTAssertEqual(decoded.tagVocabulary[0].colorHex, "#5A4FCF")
        XCTAssertNil(decoded.tagVocabulary[1].colorHex)
    }

    /// The load-bearing backward-compat test. Mirrors the
    /// `VaultTests.testLegacySchemaDecodesWithoutIsVault` pattern: a
    /// settings.json written before tags shipped must decode cleanly
    /// with an empty vocabulary instead of throwing and triggering
    /// `SettingsStore.load`'s silent error path (which would reset
    /// every other user setting to defaults).
    func testLegacySettingsJsonDecodesWithoutTagVocabulary() throws {
        let legacyJson = """
            {
                "autoBackupEnabled": true,
                "backupPath": "",
                "backupRetentionDays": 14,
                "lastBackupAt": "",
                "defaultExportDirectory": "",
                "todayQueries": [],
                "todayQueriesSeeded": false,
                "forecastDays": 30,
                "themeID": "royalPurple",
                "appearance": "system",
                "userThemes": []
            }
        """
        let data = legacyJson.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.tagVocabulary, [], "Missing key must default to []")
        XCTAssertEqual(decoded.themeID, "royalPurple",
                       "Other settings must survive the decode unchanged")
    }
}
