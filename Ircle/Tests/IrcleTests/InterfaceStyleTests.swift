import Foundation
import Testing
@testable import Ircle

/// The Clean/Classic interface-style setting: a new field on `AppSettings`, so
/// it must default to `.clean`, survive a Codable round-trip, and not break
/// decoding of older `settings.json` documents that predate the field.
@Suite("Interface style setting")
struct InterfaceStyleTests {

    @Test func defaultsToClean() {
        #expect(AppSettings().interfaceStyle == .clean)
    }

    @Test func roundTripsThroughCodable() throws {
        var s = AppSettings()
        s.interfaceStyle = .classic
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(back.interfaceStyle == .classic)
    }

    @Test func legacyDocumentWithoutFieldDecodesAsClean() throws {
        // A pre-feature settings.json has no `interfaceStyle` key at all.
        let legacy = #"{"appearance":"graphite","showTimestamps":true,"fontSize":13}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        #expect(s.interfaceStyle == .clean)
        #expect(s.appearance == .graphite)   // sanity: other fields still decode
    }

    @Test func allStylesAreSelectable() {
        #expect(InterfaceStyle.allCases.count == 3)
        #expect(InterfaceStyle.allCases.contains(.clean))
        #expect(InterfaceStyle.allCases.contains(.classic))
        #expect(InterfaceStyle.allCases.contains(.floating))
    }

    @Test func floatingRoundTripsAndHasName() throws {
        var s = AppSettings()
        s.interfaceStyle = .floating
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.interfaceStyle == .floating)
        #expect(!InterfaceStyle.floating.displayName.isEmpty)
    }
}
