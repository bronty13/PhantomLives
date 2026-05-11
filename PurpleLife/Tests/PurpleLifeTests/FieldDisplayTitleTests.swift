import XCTest
@testable import PurpleLife

/// Regression coverage for the title-resolution fix: every `FieldDisplay`
/// call site that renders a record's title (detail header, quick switcher,
/// link picker, list footers, today panels) routes through
/// `FieldDisplay.title(of:in:)`. The Weight type's primary field is
/// numeric (`pounds`); before the fix, the function's `as? String` cast
/// failed and *every* Weight record displayed as "Untitled" — a bug that
/// surfaced when the user looked at imported entries but actually
/// affected manually-created records too.
@MainActor
final class FieldDisplayTitleTests: XCTestCase {

    private func record(typeId: String, fields: [String: Any]) throws -> ObjectRecord {
        let json = String(
            data: try JSONSerialization.data(withJSONObject: fields),
            encoding: .utf8
        ) ?? "{}"
        let now = ISO8601DateFormatter().string(from: Date())
        return ObjectRecord(
            id: UUID().uuidString,
            typeId: typeId,
            parentId: nil,
            fieldsJSON: json,
            createdAt: now,
            updatedAt: now
        )
    }

    func testNumericPrimaryFieldRendersAsFormattedNumber() throws {
        // Weight's primary field is numeric (`pounds`) — the regression case.
        let weight = SchemaSeed.weight
        let key = weight.primaryFieldKey ?? ""
        let r = try record(typeId: "Weight", fields: [key: 180.5])
        XCTAssertEqual(FieldDisplay.title(of: r, in: weight), "180.5")
    }

    func testIntegerNumericPrimaryRenders() throws {
        let weight = SchemaSeed.weight
        let key = weight.primaryFieldKey ?? ""
        let r = try record(typeId: "Weight", fields: [key: 200])
        // `numberValueOrNil` formats Doubles with `.formatted()`; integers
        // come through as either Int or Double depending on how the JSON
        // decoder typed them. Both routes must produce a sensible title
        // rather than "Untitled".
        let title = FieldDisplay.title(of: r, in: weight)
        XCTAssertNotEqual(title, "Untitled", "integer-valued numeric primary must not be 'Untitled'")
        XCTAssertTrue(title.hasPrefix("200"), "expected title to start with '200', got '\(title)'")
    }

    func testNumericPrimaryFallsBackToUntitledWhenMissing() throws {
        // Defensive: a Weight record with no `pounds` (shouldn't happen
        // since the field is the primary, but the field isn't required at
        // the schema level) should still degrade gracefully.
        let weight = SchemaSeed.weight
        let r = try record(typeId: "Weight", fields: [:])
        XCTAssertEqual(FieldDisplay.title(of: r, in: weight), "Untitled")
    }

    func testTextPrimaryFieldUnchanged() throws {
        // Confirm the fix didn't regress the existing text-primary path.
        let person = SchemaSeed.person
        let key = person.primaryFieldKey ?? ""
        let r = try record(typeId: "Person", fields: [key: "Ada Lovelace"])
        XCTAssertEqual(FieldDisplay.title(of: r, in: person), "Ada Lovelace")
    }

    func testEmptyTextPrimaryStillUntitled() throws {
        let person = SchemaSeed.person
        let key = person.primaryFieldKey ?? ""
        let r = try record(typeId: "Person", fields: [key: ""])
        XCTAssertEqual(FieldDisplay.title(of: r, in: person), "Untitled")
    }
}
