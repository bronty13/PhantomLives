import Foundation
import Testing
@testable import Ircle

/// Modern mode + the custom-theme library are new `AppSettings` fields, so they
/// must default to OFF / empty, survive a Codable round-trip, and never break
/// decoding of a legacy `settings.json` that predates them.
@MainActor
@Suite("Modern mode setting")
struct ModernModeSettingsTests {

    @Test func defaultsOff() {
        let s = AppSettings()
        #expect(s.modernModeEnabled == false)
        #expect(s.modernThemeID == ModernTheme.defaultID)
        #expect(s.userThemes.isEmpty)
    }

    @Test func roundTripsWithUserThemes() throws {
        var s = AppSettings()
        s.modernModeEnabled = true
        s.modernThemeID = "dracula"
        s.userThemes = [ModernTheme.duplicate(of: ModernTheme.named("nord")!, name: "Mine")]
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(back.modernModeEnabled)
        #expect(back.modernThemeID == "dracula")
        #expect(back.userThemes.count == 1)
        #expect(back.userThemes.first?.name == "Mine")
    }

    @Test func legacyDocumentDecodesWithModernOff() throws {
        // A pre-feature settings.json has none of the modern keys.
        let legacy = ##"{"appearance":"graphite","showTimestamps":true,"fontSize":13}"##
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        #expect(s.modernModeEnabled == false)         // the retro-unchanged guarantee
        #expect(s.modernThemeID == ModernTheme.defaultID)
        #expect(s.userThemes.isEmpty)
        #expect(s.appearance == .graphite)            // sanity: other fields still decode
    }

    @Test func exportImportRoundTripGetsAFreshID() throws {
        let store = SettingsStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString), secretStore: InMemorySecretStore())
        let original = ModernTheme.duplicate(of: ModernTheme.named("paper")!, name: "Shared")

        // Export → a .ircletheme is just the JSON of one ModernTheme.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).ircletheme")
        try JSONEncoder().encode(original).write(to: url)

        // Import stamps a fresh id so it can't collide with the source.
        let imported = ThemeImporter.importTheme(from: url, into: store)
        #expect(imported != nil)
        #expect(imported?.id != original.id)
        #expect(imported?.name == "Shared")
        #expect(imported?.windowBG == original.windowBG)
        #expect(store.settings.userThemes.count == 1)
        try? FileManager.default.removeItem(at: url)
    }
}
