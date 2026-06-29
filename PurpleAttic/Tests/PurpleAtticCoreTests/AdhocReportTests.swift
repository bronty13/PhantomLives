import XCTest
@testable import PurpleAtticCore

/// Covers the pure ad-hoc report renderers (CSV / JSON / text) — no filesystem touched.
final class AdhocReportTests: XCTestCase {

    private func f(_ path: String, _ size: Int64) -> AdhocFile {
        AdhocFile(path: path, name: (path as NSString).lastPathComponent, size: size,
                  modTime: Date(timeIntervalSince1970: 1_700_000_000), isDir: false,
                  lastSeen: Date(timeIntervalSince1970: 0))
    }

    func testCSVHasHeaderAndOneRowPerFile() {
        let csv = AdhocReport.csv([f("a/x.pdf", 10), f("b.txt", 20)])
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.first, "path,name,size,modified,isDir,sha1,tier")
        XCTAssertEqual(lines.count, 3, "header + 2 rows")
        XCTAssertTrue(csv.contains("a/x.pdf"))
    }

    func testCSVEscapesCommasInNames() {
        let csv = AdhocReport.csv([f("weird, name.txt", 1)])
        XCTAssertTrue(csv.contains("\"weird, name.txt\""), "a value with a comma must be quoted")
    }

    func testJSONIsSortedArrayOfRows() {
        let json = AdhocReport.json([f("b.txt", 6), f("a.txt", 5)])
        let arr = try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [[String: Any]]
        XCTAssertEqual(arr.count, 2)
        XCTAssertEqual(arr.first?["path"] as? String, "a.txt", "rows are sorted by path")
        XCTAssertNil(arr.first?["lastSeen"], "the cache-internal lastSeen must not leak into the report")
    }

    func testTxtSummaryHasCountAndItems() {
        let txt = AdhocReport.txt([f("a", 10), f("b", 20)], generatedAt: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(txt.contains("Items: 2"))
        XCTAssertTrue(txt.contains("PurpleAttic"))
    }

    func testRenderDispatchesByFormat() {
        let files = [f("a", 1)]
        let at = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(AdhocReport.render(files, format: .csv, generatedAt: at).hasPrefix("path,"))
        XCTAssertTrue(AdhocReport.render(files, format: .json, generatedAt: at).hasPrefix("["))
        XCTAssertTrue(AdhocReport.render(files, format: .txt, generatedAt: at).contains("PurpleAttic"))
    }
}
