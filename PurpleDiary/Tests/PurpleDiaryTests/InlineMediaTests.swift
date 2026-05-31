import XCTest
@testable import PurpleDiary

/// Inline media in entry bodies: the ref convention, the segment parser that
/// drives in-place rendering, and the Day One moment→attachment rewrite.
final class InlineMediaTests: XCTestCase {

    func testRefAndScheme() {
        XCTAssertEqual(InlineMedia.ref(attachmentId: "A1", caption: "sunset"),
                       "![sunset](pd-attachment://A1)")
        XCTAssertTrue(InlineMedia.hasInlineMedia("text ![x](pd-attachment://A1) more"))
        XCTAssertFalse(InlineMedia.hasInlineMedia("just text"))
    }

    func testParseSplitsTextAndMediaInOrder() {
        let body = "before\n\n![a beach](pd-attachment://IMG1)\n\nafter"
        let segs = InlineMedia.parse(body)
        XCTAssertEqual(segs.count, 3)
        XCTAssertEqual(segs[0], .text("before\n\n"))
        XCTAssertEqual(segs[1], .media(id: "IMG1", caption: "a beach"))
        XCTAssertEqual(segs[2], .text("\n\nafter"))
    }

    func testParsePlainTextIsSingleSegment() {
        XCTAssertEqual(InlineMedia.parse("no media here"), [.text("no media here")])
    }

    func testParseConsecutiveMedia() {
        let segs = InlineMedia.parse("![](pd-attachment://A)![](pd-attachment://B)")
        XCTAssertEqual(segs, [.media(id: "A", caption: ""), .media(id: "B", caption: "")])
    }

    func testRewriteDayOneBodyMapsRefsInPlaceAndKeepsProse() {
        let body = "Walk ![beach](dayone-moment://M1) then lunch ![](dayone-moment:/video/M2) home."
        let out = InlineMedia.rewriteDayOneBody(body, momentToAttachment: ["M1": "att1", "M2": "att2"])
        XCTAssertEqual(out, "Walk ![beach](pd-attachment://att1) then lunch ![](pd-attachment://att2) home.")
    }

    func testRewriteDayOneBodyFallsBackToMarkerForUnmappedRefs() {
        let out = InlineMedia.rewriteDayOneBody("see ![sunset](dayone-moment://X) here",
                                                momentToAttachment: [:])
        XCTAssertFalse(out.contains("dayone-moment"))
        XCTAssertTrue(out.contains("📷 sunset"))
        XCTAssertTrue(out.contains("see "))
        XCTAssertTrue(out.contains(" here"))
    }
}
