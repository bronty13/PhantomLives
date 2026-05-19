import XCTest
@testable import PurpleReel

final class FCPXMLWriterTests: XCTestCase {

    private func makeInputs() -> [FCPXMLExportInput] {
        let asset = Asset(rowId: 1,
                          path: "/Volumes/A1/Footage/Day 1 — A & B/clip 1.mov",
                          filename: "clip 1.mov",
                          sizeBytes: 1_000_000,
                          modifiedAt: Date(),
                          codec: "avc1",
                          widthPx: 1920,
                          heightPx: 1080,
                          durationSeconds: 5.0,
                          frameRate: 29.97,
                          sha1: nil,
                          addedAt: Date())
        let markers = [
            Marker(id: 1, assetId: 1, timecodeIn: 1.0,
                    timecodeOut: nil, note: "hero",
                    createdAt: Date()),
            Marker(id: 2, assetId: 1, timecodeIn: 2.5,
                    timecodeOut: nil, note: "cutaway <ref>",
                    createdAt: Date()),
        ]
        let subs = [
            Subclip(id: 1, parentAssetId: 1, name: "select A",
                     timecodeIn: 1.0, timecodeOut: 2.5,
                     createdAt: Date()),
        ]
        let tags = [Tag(id: 1, name: "interview"),
                    Tag(id: 2, name: "selects")]
        let rating = Rating(assetId: 1, stars: 5,
                              colorLabel: nil, description: nil)
        return [FCPXMLExportInput(asset: asset, markers: markers,
                                    subclips: subs, tags: tags,
                                    rating: rating)]
    }

    func testEmittedXMLIsWellFormed() throws {
        let xml = FCPXMLWriter.makeXML(eventName: "Test Event",
                                         items: makeInputs(),
                                         toolVersion: "0.1.0")
        XCTAssertNoThrow(try XMLDocument(xmlString: xml, options: []))
    }

    func testFormatPickedFor2997IsNTSC() {
        let xml = FCPXMLWriter.makeXML(eventName: "T",
                                         items: makeInputs(),
                                         toolVersion: "0.1.0")
        XCTAssertTrue(xml.contains(#"name="FFVideoFormat1080p2997""#))
        XCTAssertTrue(xml.contains(#"frameDuration="1001/30000s""#))
    }

    func testMarkersSubclipsTagsAndRatingsRender() {
        let xml = FCPXMLWriter.makeXML(eventName: "T",
                                         items: makeInputs(),
                                         toolVersion: "0.1.0")
        // Two markers.
        XCTAssertEqual(xml.components(separatedBy: "<marker ").count - 1, 2)
        // Tags joined as keyword value.
        XCTAssertTrue(xml.contains(#"value="interview, selects""#))
        // 5-star rating maps to Favorite.
        XCTAssertTrue(xml.contains(#"<rating name="Favorite""#))
        // One asset-clip for the master, one for the subclip = 2.
        XCTAssertEqual(xml.components(separatedBy: "<asset-clip ").count - 1, 2)
    }

    func testSpecialCharactersAreXMLEscaped() {
        let xml = FCPXMLWriter.makeXML(eventName: "T",
                                         items: makeInputs(),
                                         toolVersion: "0.1.0")
        // Marker note "cutaway <ref>" goes through XML escape.
        XCTAssertTrue(xml.contains("cutaway &lt;ref&gt;"))
        // The asset path has spaces (→ %20), an em-dash (→ %E2%80%94),
        // and an ampersand. The em-dash + spaces are percent-encoded
        // for URL validity, AND the ampersand is XML-escaped so the
        // emitted file:// URL is safe inside an XML attribute.
        XCTAssertTrue(xml.contains("%20"),
                       "spaces in path should be percent-encoded for URL validity")
        XCTAssertTrue(xml.contains("%E2%80%94"),
                       "em-dash should be percent-encoded")
        // The raw `&` from the path must NOT appear unescaped in XML
        // output — only as the XML entity reference `&amp;`.
        XCTAssertTrue(xml.contains("A%20&amp;%20B"),
                       "ampersand inside file:// URL must be XML-escaped")
    }

    func testLowRatingDoesNotEmitFavorite() {
        // C11 changed the default `favoritesMinStars` from a hard-
        // coded 4 to 1 (Kyno-parity dialog default). This test pins
        // the strict-threshold path explicitly: a 2★ clip exported
        // with min = 4 should NOT mark Favorite.
        var inputs = makeInputs()
        inputs[0] = FCPXMLExportInput(
            asset: inputs[0].asset,
            markers: inputs[0].markers,
            subclips: inputs[0].subclips,
            tags: inputs[0].tags,
            rating: Rating(assetId: 1, stars: 2, colorLabel: nil, description: nil)
        )
        var opts = FCPXMLExportOptions.defaults
        opts.favoritesMinStars = 4
        let xml = FCPXMLWriter.makeXML(eventName: "T", items: inputs,
                                         toolVersion: "0.1.0",
                                         options: opts)
        XCTAssertFalse(xml.contains(#"<rating name="Favorite""#))
    }
}
