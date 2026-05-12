import XCTest
import AppKit
@testable import PurpleLife

/// Slice B1 — storage shape for the new `.richText` field kind. Lives
/// inside `fields_json` as `{ rtf: <base64>, plain: <mirror> }`. These
/// tests pin the encode/decode contract before slice B2's editor view
/// builds on top of it.
final class RichTextValueTests: XCTestCase {

    // MARK: - JSON shape

    func test_jsonDictionaryRoundtripPreservesBothKeys() {
        let value = RichTextValue(rtf: Data([0xDE, 0xAD, 0xBE, 0xEF]),
                                  plain: "hello world")
        let dict = value.jsonDictionary
        XCTAssertEqual(dict["plain"] as? String, "hello world")
        XCTAssertEqual(dict["rtf"] as? String, "3q2+7w==")

        let decoded = RichTextValue.from(jsonDictionary: dict)
        XCTAssertEqual(decoded.plain, "hello world")
        XCTAssertEqual(decoded.rtf, Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    func test_jsonDictionaryDecodeIsTolerantOfMissingKeys() {
        XCTAssertEqual(RichTextValue.from(jsonDictionary: [:]).plain, "")
        XCTAssertEqual(RichTextValue.from(jsonDictionary: [:]).rtf, Data())

        let plainOnly = RichTextValue.from(jsonDictionary: ["plain": "just text"])
        XCTAssertEqual(plainOnly.plain, "just text")
        XCTAssertEqual(plainOnly.rtf, Data())

        // Bad base64 yields empty rtf but doesn't crash.
        let badRtf = RichTextValue.from(jsonDictionary: ["rtf": "!!!not base64!!!", "plain": "x"])
        XCTAssertEqual(badRtf.plain, "x")
        XCTAssertEqual(badRtf.rtf, Data())
    }

    // MARK: - NSAttributedString conversion

    func test_fromAttributedStringPicksRTFForPlainText() {
        let attr = NSAttributedString(string: "body text")
        let v = RichTextValue.from(attributedString: attr)
        XCTAssertEqual(v.plain, "body text")
        XCTAssertGreaterThan(v.rtf.count, 0)
        // A reasonably-shaped RTF document starts with "{\\rtf"
        let prefix = String(data: v.rtf.prefix(8), encoding: .ascii) ?? ""
        XCTAssertTrue(prefix.hasPrefix("{\\rtf"), "Expected RTF magic, got: \(prefix)")
    }

    func test_fromAttributedStringEmptyYieldsEmptyRTF() {
        let v = RichTextValue.from(attributedString: NSAttributedString())
        XCTAssertEqual(v.plain, "")
        XCTAssertEqual(v.rtf, Data())
    }

    // MARK: - Size budget

    func test_richTextLimitsFitsAndShouldWarn() {
        XCTAssertTrue(RichTextLimits.fits(Data(count: 100)))
        XCTAssertTrue(RichTextLimits.fits(Data(count: RichTextLimits.maxBlobBytes)))
        XCTAssertFalse(RichTextLimits.fits(Data(count: RichTextLimits.maxBlobBytes + 1)))

        XCTAssertFalse(RichTextLimits.shouldWarn(Data(count: 100)))
        XCTAssertTrue(RichTextLimits.shouldWarn(Data(count: RichTextLimits.warnBytes + 1)))
    }

    // MARK: - FTS integration

    @MainActor
    func test_searchableTextIncludesRichTextPlainMirror() throws {
        // A bare type with a single richText field. The FTS body must
        // pick up the plain mirror so a user typing a word from the
        // note's body finds the record.
        let bodyField = FieldDef.make(name: "Body", kind: .richText)
        let type = ObjectType.builtIn(
            id: "TestNote",
            name: "Test Note",
            pluralName: "Test Notes",
            systemImage: "doc.text",
            colorHex: "#888888",
            fields: [bodyField],
            primaryFieldKey: nil
        )
        let record = ObjectRecord.make(typeId: type.id, fields: [
            bodyField.key: ["rtf": "ignored", "plain": "alpha beta gamma"]
        ])
        let (_, body) = SearchService.searchableText(for: record, type: type)
        XCTAssertTrue(body.contains("alpha beta gamma"),
                      "FTS body must include the richText plain mirror; got: '\(body)'")
    }

    @MainActor
    func test_searchableTextSkipsMissingPlainMirror() throws {
        let bodyField = FieldDef.make(name: "Body", kind: .richText)
        let type = ObjectType.builtIn(
            id: "TestNote",
            name: "Test Note",
            pluralName: "Test Notes",
            systemImage: "doc.text",
            colorHex: "#888888",
            fields: [bodyField],
            primaryFieldKey: nil
        )
        // No `plain` key — body should not contain "rtf base64 garbage".
        let record = ObjectRecord.make(typeId: type.id, fields: [
            bodyField.key: ["rtf": "deadbeef-base64"]
        ])
        let (_, body) = SearchService.searchableText(for: record, type: type)
        XCTAssertFalse(body.contains("deadbeef"),
                       "FTS body must not surface the encoded RTF blob")
    }
}
