import XCTest
@testable import PurpleAtticCore

/// osxphotos `--json` emits non-standard `Infinity`/`-Infinity`/`NaN` literals (audio
/// `energyValues`, unset scores). Python tolerates them; Swift's JSON parser rejects them and
/// failed the whole purge preview. `sanitizeNonFiniteLiterals` strips them in value position
/// while leaving strings (incl. a keyword/album literally containing "Infinity"/"NaN") intact.
final class PhotoMetadataTests: XCTestCase {

    private func sanitizedString(_ json: String) -> String {
        String(data: PhotoMetadataQuery.sanitizeNonFiniteLiterals(Data(json.utf8)), encoding: .utf8)!
    }

    func testValuePositionLiteralsBecomeNull() {
        XCTAssertEqual(sanitizedString(#"{"a": Infinity}"#),  #"{"a": null}"#)
        XCTAssertEqual(sanitizedString(#"{"a": -Infinity}"#), #"{"a": null}"#)
        XCTAssertEqual(sanitizedString(#"{"a": NaN}"#),       #"{"a": null}"#)
        XCTAssertEqual(sanitizedString(#"{"e": [-Infinity, NaN, Infinity]}"#),
                       #"{"e": [null, null, null]}"#)
    }

    func testNegativeNumbersAndNormalValuesUntouched() {
        XCTAssertEqual(sanitizedString(#"{"x": -63.25, "y": 0, "z": -1}"#),
                       #"{"x": -63.25, "y": 0, "z": -1}"#)
    }

    func testStringsContainingTheLiteralsAreUntouched() {
        // The dangerous case: a keyword/album/caption that literally contains the words.
        let s = #"{"k": ["Infinity", "NaN Land"], "cap": "to Infinity and beyond"}"#
        XCTAssertEqual(sanitizedString(s), s, "literals inside strings must be preserved verbatim")
    }

    func testEscapedQuotesInStringsDontBreakStringTracking() {
        // A backslash-escaped quote must not prematurely end the string and expose "Infinity".
        let s = #"{"cap": "a \"Infinity\" sign", "v": NaN}"#
        XCTAssertEqual(sanitizedString(s), #"{"cap": "a \"Infinity\" sign", "v": null}"#)
    }

    func testRecordWithNonFiniteLiteralsDecodesAndPreservesStringData() throws {
        let json = #"""
        [{"uuid":"U1","date":"2020-01-01T00:00:00-05:00","favorite":false,
          "albums":["NaN Land"],"keywords":["Infinity","save"],
          "original_filename":"IMG_1.HEIC","original_filesize":123,
          "ismissing":false,"intrash":false,
          "score":NaN,"audio":[{"energyValues":-Infinity},{"energyValues":Infinity}]}]
        """#
        let cleaned = PhotoMetadataQuery.sanitizeNonFiniteLiterals(Data(json.utf8))
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        let recs = try dec.decode([OsxphotosRecord].self, from: cleaned)
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs[0].uuid, "U1")
        XCTAssertEqual(recs[0].keywords, ["Infinity", "save"], "keyword 'Infinity' must survive")
        XCTAssertEqual(recs[0].albums, ["NaN Land"], "album 'NaN Land' must survive")
        XCTAssertEqual(recs[0].originalFilesize, 123)
        XCTAssertFalse(recs[0].favorite)
    }
}
