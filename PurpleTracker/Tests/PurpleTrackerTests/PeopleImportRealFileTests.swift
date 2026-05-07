import XCTest
@testable import PurpleTracker

@MainActor
final class PeopleImportRealFileTests: XCTestCase {
    /// Manual diagnostic — imports the real ADP file from ~/Downloads and
    /// reports counts. Skipped automatically if the file isn't present.
    func testImportRealADPFile() throws {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Downloads/ADP_IMP_UserFeed_2026-04-17.csv")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Real ADP file not present at \(url.path)")
        }
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? ""
        let rows = PeopleService.parseCSV(text)
        print("DIAG rows.count = \(rows.count)")
        XCTAssertGreaterThan(rows.count, 1, "Expected header + at least one data row")
        if rows.count > 1 {
            print("DIAG header = \(rows[0])")
            print("DIAG firstDataRow = \(rows[1])")
        }
        // Find the Associate ID column index using the same logic as the importer
        let header = rows[0].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let aidIdx = header.firstIndex(of: "associate id") ?? -1
        print("DIAG aidIdx = \(aidIdx)")
        var nonEmpty = 0
        for r in rows.dropFirst() {
            if aidIdx >= 0 && aidIdx < r.count
               && !r[aidIdx].trimmingCharacters(in: .whitespaces).isEmpty {
                nonEmpty += 1
            }
        }
        print("DIAG non-empty AID rows = \(nonEmpty)")
        // The ADP feed has many FEAD-only rows with blank AID; the active
        // employee count is in the low thousands, so anything > 1000 means
        // the parser is working and not collapsing the file into one giant row.
        XCTAssertGreaterThan(nonEmpty, 1000,
            "Parser should yield thousands of non-empty AID rows from a real ADP feed")
    }

    /// Targeted regression test for the CRLF grapheme-cluster bug: Swift treats
    /// `\r\n` as a single `Character`, so a parser that switches on
    /// `Character` values (rather than `Unicode.Scalar`) silently swallows
    /// every Windows line ending and collapses the file into one row.
    func testParserHandlesCRLFLineEndings() {
        let csv = "a,b,c\r\n1,2,3\r\n4,5,6\r\n"
        let rows = PeopleService.parseCSV(csv)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], ["a", "b", "c"])
        XCTAssertEqual(rows[1], ["1", "2", "3"])
        XCTAssertEqual(rows[2], ["4", "5", "6"])
    }

    func testParserHandlesBOMAndMixedEndings() {
        let csv = "\u{FEFF}a,b\r1,2\n3,4\r\n"
        let rows = PeopleService.parseCSV(csv)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], ["a", "b"])
        XCTAssertEqual(rows[1], ["1", "2"])
        XCTAssertEqual(rows[2], ["3", "4"])
    }

    /// Verifies the auto-import scan picks the *latest* ADP file by filename
    /// sort (which happens to match calendar order because the ADP rotation
    /// uses ISO-8601 dates).
    func testLatestADPFileScanPicksNewestByFilename() throws {
        let downloads = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: downloads.path)) ?? []
        let adpFiles = names.filter { $0.hasPrefix("ADP_IMP_UserFeed_") && $0.hasSuffix(".csv") }
        guard !adpFiles.isEmpty else {
            throw XCTSkip("No ADP_IMP_UserFeed_*.csv files in ~/Downloads to verify against")
        }
        let expected = adpFiles.sorted().last!
        let url = PeopleService.latestADPFileInDownloads()
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.lastPathComponent, expected,
                       "latestADPFileInDownloads must return the lexicographically last match")
    }
}
