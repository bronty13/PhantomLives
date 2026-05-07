import XCTest
@testable import Timeliner

final class ModelCodableTests: XCTestCase {

    func testCaseRoundTrip() throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let original = Case(
            id: UUID().uuidString,
            title: "Sample",
            caseDescription: "Two-line\ndescription with `code` and **bold**",
            status: "cold",
            pinned: true,
            createdAt: now,
            updatedAt: now
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Case.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testEventRoundTripPreservesEnumAndOptionalDateEnd() throws {
        let now = ISO8601DateFormatter().string(from: Date())
        var ev = Event(
            id: UUID().uuidString,
            caseId: "case",
            title: "T",
            dateStart: now,
            dateEnd: nil,
            descriptionMarkdown: "**bold**",
            sourceURL: "https://example.com",
            importance: Importance.high.rawValue,
            createdAt: now
        )
        ev.importanceEnum = .critical
        let data = try JSONEncoder().encode(ev)
        let decoded = try JSONDecoder().decode(Event.self, from: data)
        XCTAssertEqual(decoded.importanceEnum, .critical)
        XCTAssertNil(decoded.dateEnd)
    }

    func testImportanceFilledPipsOrder() {
        XCTAssertEqual(Importance.low.filledPips,      1)
        XCTAssertEqual(Importance.medium.filledPips,   2)
        XCTAssertEqual(Importance.high.filledPips,     3)
        XCTAssertEqual(Importance.critical.filledPips, 4)
    }

    func testHexColorRoundTrip() {
        let hex = "#FF7A33"
        let color = Color(hex: hex)
        XCTAssertNotNil(color)
        XCTAssertEqual(color?.toHex(), hex)
    }

    func testEventDateParserAcceptsBothFormats() {
        // ISO with TZ
        XCTAssertNotNil(EventDateParser.parse("2026-05-06T12:00:00Z"))
        // Date only
        XCTAssertNotNil(EventDateParser.parse("2026-05-06"))
        // Garbage
        XCTAssertNil(EventDateParser.parse("not-a-date"))
    }
}

import SwiftUI
