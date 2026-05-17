import XCTest
@testable import PurpleReel

final class MHLWriterTests: XCTestCase {

    func testEmittedXMLIsWellFormedAndCarriesAllEntryFields() throws {
        let start = ISO8601DateFormatter().date(from: "2026-05-17T10:00:00Z")!
        let finish = ISO8601DateFormatter().date(from: "2026-05-17T10:05:00Z")!
        let entries: [MHLEntry] = [
            MHLEntry(relativePath: "clips/A.mov",
                     sizeBytes: 524288,
                     lastModified: ISO8601DateFormatter().date(from: "2026-05-17T09:00:00Z")!,
                     hash: "da14852f8403e5958876419285accdb75d23a9af",
                     hashAlgorithm: .sha1,
                     hashDate: ISO8601DateFormatter().date(from: "2026-05-17T10:01:00Z")!),
            MHLEntry(relativePath: "README & notes.txt",
                     sizeBytes: 64,
                     lastModified: ISO8601DateFormatter().date(from: "2026-05-17T09:30:00Z")!,
                     hash: "4041b766c2b9149a0d980a6216c027fef38e7653",
                     hashAlgorithm: .sha1,
                     hashDate: ISO8601DateFormatter().date(from: "2026-05-17T10:02:00Z")!),
        ]

        let xml = MHLWriter.makeXML(entries: entries,
                                     rootName: "test-card",
                                     startDate: start,
                                     finishDate: finish,
                                     toolVersion: "0.1.0")

        // 1. Well-formed XML — round-trip through XMLDocument.
        XCTAssertNoThrow(try XMLDocument(xmlString: xml, options: []))

        // 2. Carries the v1.1 hashlist declaration.
        XCTAssertTrue(xml.contains(#"<hashlist version="1.1">"#))

        // 3. Both per-file fields are present with correct hashes.
        XCTAssertTrue(xml.contains("da14852f8403e5958876419285accdb75d23a9af"))
        XCTAssertTrue(xml.contains("4041b766c2b9149a0d980a6216c027fef38e7653"))

        // 4. XML special characters in paths are escaped.
        XCTAssertTrue(xml.contains("README &amp; notes.txt"))
        XCTAssertFalse(xml.contains("README & notes.txt"))

        // 5. Creator info carries the tool version.
        XCTAssertTrue(xml.contains("<tool>PurpleReel 0.1.0</tool>"))
    }

    func testSHA256AndMD5UseCorrectElementName() {
        let baseDate = Date()
        let sha256Entry = MHLEntry(
            relativePath: "a", sizeBytes: 1, lastModified: baseDate,
            hash: "deadbeef", hashAlgorithm: .sha256, hashDate: baseDate
        )
        let md5Entry = MHLEntry(
            relativePath: "b", sizeBytes: 1, lastModified: baseDate,
            hash: "cafebabe", hashAlgorithm: .md5, hashDate: baseDate
        )
        let xml = MHLWriter.makeXML(entries: [sha256Entry, md5Entry],
                                      rootName: "x",
                                      startDate: baseDate,
                                      finishDate: baseDate,
                                      toolVersion: "test")
        XCTAssertTrue(xml.contains("<sha256>deadbeef</sha256>"))
        XCTAssertTrue(xml.contains("<md5>cafebabe</md5>"))
    }
}
