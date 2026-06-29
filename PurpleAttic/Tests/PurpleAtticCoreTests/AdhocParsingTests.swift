import XCTest
@testable import PurpleAtticCore

/// Covers the pure rclone-output parsers (`RcloneParse`) against captured fixtures — lsjson listing,
/// the `check --combined` diff, and the nanosecond-RFC3339 timestamp rclone emits. No process or
/// network: a parser regression can't silently corrupt the cache or the diff view.
final class AdhocParsingTests: XCTestCase {

    // MARK: - lsjson

    func testLsjsonParsesFilesWithHashAndMetadata() {
        let json = """
        [
          {"Path":"Invoices/2026-Q2.pdf","Name":"2026-Q2.pdf","Size":20480,"MimeType":"application/pdf",
           "ModTime":"2026-06-28T21:00:00.123456789Z","IsDir":false,"Hashes":{"SHA-1":"abc123"},
           "ID":"4_zxyz","Tier":"hot"},
          {"Path":"notes.txt","Name":"notes.txt","Size":12,"MimeType":"text/plain",
           "ModTime":"2026-01-01T00:00:00.000000000Z","IsDir":false}
        ]
        """.data(using: .utf8)!

        let files = RcloneParse.lsjson(json)
        XCTAssertEqual(files.count, 2)

        let pdf = files[0]
        XCTAssertEqual(pdf.path, "Invoices/2026-Q2.pdf")
        XCTAssertEqual(pdf.name, "2026-Q2.pdf")
        XCTAssertEqual(pdf.size, 20480)
        XCTAssertEqual(pdf.mimeType, "application/pdf")
        XCTAssertEqual(pdf.sha1, "abc123", "B2 SHA-1 must be lifted out of the Hashes map")
        XCTAssertEqual(pdf.id, "4_zxyz")
        XCTAssertEqual(pdf.tier, "hot")
        XCTAssertFalse(pdf.isDir)

        let txt = files[1]
        XCTAssertEqual(txt.size, 12)
        XCTAssertNil(txt.sha1, "absent Hashes → nil, not a crash")
        XCTAssertNil(txt.id)
    }

    func testLsjsonToleratesGarbage() {
        XCTAssertTrue(RcloneParse.lsjson(Data("not json".utf8)).isEmpty)
        XCTAssertTrue(RcloneParse.lsjson(Data("{}".utf8)).isEmpty)
        XCTAssertTrue(RcloneParse.lsjson(Data("[]".utf8)).isEmpty)
    }

    // MARK: - check --combined diff

    func testCheckCombinedClassifiesChanges() {
        let text = """
        * Invoices/2026-Q2.pdf
        + new/photo.jpg
        = unchanged.txt
        ! broken/path
        """
        let entries = RcloneParse.checkCombined(text)
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[0], DiffEntry(change: .differ, path: "Invoices/2026-Q2.pdf"))
        XCTAssertEqual(entries[1], DiffEntry(change: .onlyLocal, path: "new/photo.jpg"))
        XCTAssertEqual(entries[2], DiffEntry(change: .same, path: "unchanged.txt"))
        XCTAssertEqual(entries[3], DiffEntry(change: .error, path: "broken/path"))

        // Only changed (*) and only-local (+) would be uploaded by an additive backup.
        XCTAssertEqual(entries.filter { $0.needsUpload }.count, 2)
    }

    func testCheckCombinedIgnoresBlankAndUnknownLines() {
        let entries = RcloneParse.checkCombined("\n\n? weird line\n+ ok.txt\n")
        XCTAssertEqual(entries, [DiffEntry(change: .onlyLocal, path: "ok.txt")])
    }

    // MARK: - RFC3339 with nanoseconds

    func testRfc3339ParsesNanosecondAndPlainTimestamps() {
        let ref = ISO8601DateFormatter().date(from: "2026-06-28T21:00:00Z")!

        let nanos = RcloneParse.rfc3339("2026-06-28T21:00:00.123456789Z")
        XCTAssertNotNil(nanos)
        XCTAssertEqual(nanos!.timeIntervalSince1970, ref.timeIntervalSince1970, accuracy: 1.0,
                       "nanosecond fractional seconds must be tolerated (stripped to the second)")

        let plain = RcloneParse.rfc3339("2026-06-28T21:00:00Z")
        XCTAssertNotNil(plain)
        XCTAssertEqual(plain!.timeIntervalSince1970, ref.timeIntervalSince1970, accuracy: 1.0)

        XCTAssertNil(RcloneParse.rfc3339("not-a-date"))
    }
}
