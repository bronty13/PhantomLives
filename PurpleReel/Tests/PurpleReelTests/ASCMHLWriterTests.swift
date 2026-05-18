import XCTest
@testable import PurpleReel

/// ASC-MHL v2.0 writer parity tests. Schema reference:
/// https://asc-mhl.org/
final class ASCMHLWriterTests: XCTestCase {

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func makeEntry(path: String = "clips/A.mov",
                            size: Int64 = 524_288,
                            hash: String = "deadbeef",
                            algo: HashAlgorithm = .sha1) -> MHLEntry {
        MHLEntry(
            relativePath: path,
            sizeBytes: size,
            lastModified: isoFormatter.date(from: "2026-05-17T09:00:00Z")!,
            hash: hash,
            hashAlgorithm: algo,
            hashDate: isoFormatter.date(from: "2026-05-17T10:01:00Z")!
        )
    }

    // MARK: - Shape

    func testEmittedXMLIsWellFormed() throws {
        let start = isoFormatter.date(from: "2026-05-17T10:00:00Z")!
        let finish = isoFormatter.date(from: "2026-05-17T10:05:00Z")!
        let xml = ASCMHLWriter.makeXML(
            entries: [makeEntry()],
            rootName: "card-A",
            startDate: start,
            finishDate: finish,
            toolVersion: "0.1.0"
        )
        XCTAssertNoThrow(try XMLDocument(xmlString: xml, options: []))
    }

    func testCarriesV2NamespaceAndVersion() {
        let xml = ASCMHLWriter.makeXML(
            entries: [makeEntry()],
            rootName: "card",
            startDate: Date(), finishDate: Date(),
            toolVersion: "0.1.0"
        )
        XCTAssertTrue(xml.contains(#"xmlns="urn:ASC:MHL:v2.0""#),
            "ASC-MHL v2 namespace missing")
        XCTAssertTrue(xml.contains(#"version="2.0""#),
            "version=\"2.0\" attribute missing")
    }

    func testCarriesProcessinfoBlock() {
        let xml = ASCMHLWriter.makeXML(
            entries: [makeEntry()],
            rootName: "card",
            startDate: Date(), finishDate: Date(),
            toolVersion: "0.1.0"
        )
        XCTAssertTrue(xml.contains("<processinfo>"),
            "<processinfo> block missing — v2 spec requires one")
        XCTAssertTrue(xml.contains("<process>transfer</process>"))
        XCTAssertTrue(xml.contains("<roothash>"),
            "<roothash> with rolled-up C4 missing")
    }

    func testPathSizeAndModtimeRenderedAsAttributes() {
        // v2 attaches size + lastmodificationdate as attributes
        // on <path>, not as separate child elements (which is the
        // v1.1 shape).
        let xml = ASCMHLWriter.makeXML(
            entries: [makeEntry(path: "A.mov", size: 524_288)],
            rootName: "card",
            startDate: Date(), finishDate: Date(),
            toolVersion: "0.1.0"
        )
        XCTAssertTrue(xml.contains(#"size="524288""#),
            "size attribute missing on <path>")
        XCTAssertTrue(xml.contains("lastmodificationdate="),
            "lastmodificationdate attribute missing on <path>")
    }

    // MARK: - Algorithm-specific element names

    func testSHA1EmitsSha1Element() {
        let xml = ASCMHLWriter.makeXML(
            entries: [makeEntry(hash: "deadbeef", algo: .sha1)],
            rootName: "card",
            startDate: Date(), finishDate: Date(),
            toolVersion: "0.1.0"
        )
        XCTAssertTrue(xml.contains("<sha1"),
            "SHA-1 entries should produce <sha1> child elements")
    }

    func testSHA256EmitsSha256Element() {
        let xml = ASCMHLWriter.makeXML(
            entries: [makeEntry(hash: "deadbeef", algo: .sha256)],
            rootName: "card",
            startDate: Date(), finishDate: Date(),
            toolVersion: "0.1.0"
        )
        XCTAssertTrue(xml.contains("<sha256"))
    }

    func testC4EmitsC4Element() {
        let xml = ASCMHLWriter.makeXML(
            entries: [makeEntry(hash: "c4qwerty...", algo: .c4)],
            rootName: "card",
            startDate: Date(), finishDate: Date(),
            toolVersion: "0.1.0"
        )
        XCTAssertTrue(xml.contains("<c4"),
            "C4 entries should produce <c4> child elements")
    }

    // MARK: - XML escaping

    func testPathSpecialCharactersAreEscaped() {
        let xml = ASCMHLWriter.makeXML(
            entries: [makeEntry(path: "Reels & B-roll/A.mov")],
            rootName: "card",
            startDate: Date(), finishDate: Date(),
            toolVersion: "0.1.0"
        )
        XCTAssertTrue(xml.contains("Reels &amp; B-roll/A.mov"),
            "Ampersand in path should be XML-escaped")
        XCTAssertFalse(xml.contains("Reels & B-roll"),
            "Raw `&` should not appear in valid XML output")
    }

    // MARK: - Root-hash determinism

    func testRootHashIsDeterministicForSameEntries() {
        let entries = [
            makeEntry(path: "A.mov", hash: "h1"),
            makeEntry(path: "B.mov", hash: "h2"),
        ]
        let xml1 = ASCMHLWriter.makeXML(
            entries: entries,
            rootName: "card",
            startDate: Date(), finishDate: Date(),
            toolVersion: "0.1.0"
        )
        let xml2 = ASCMHLWriter.makeXML(
            entries: entries.reversed(),  // input order shuffled
            rootName: "card",
            startDate: Date(), finishDate: Date(),
            toolVersion: "0.1.0"
        )
        // Extract the rooth ash C4 from both — the implementation
        // path-sorts before rolling up so order doesn't matter.
        let root1 = extractRootHash(xml1)
        let root2 = extractRootHash(xml2)
        XCTAssertEqual(root1, root2,
            "Root C4 should be path-sorted and therefore order-independent")
    }

    private func extractRootHash(_ xml: String) -> String? {
        guard let openRange = xml.range(of: "<roothash>"),
              let closeRange = xml.range(of: "</roothash>")
        else { return nil }
        return String(xml[openRange.upperBound..<closeRange.lowerBound])
    }

    // MARK: - Tool info

    func testCreatorInfoIncludesPurpleReelToolElement() {
        let xml = ASCMHLWriter.makeXML(
            entries: [makeEntry()],
            rootName: "card",
            startDate: Date(), finishDate: Date(),
            toolVersion: "0.1.42"
        )
        XCTAssertTrue(xml.contains(#"name="PurpleReel""#),
            "<tool name=\"PurpleReel\" /> missing from creatorinfo")
        XCTAssertTrue(xml.contains(#"version="0.1.42""#),
            "Tool version attribute missing")
    }
}
