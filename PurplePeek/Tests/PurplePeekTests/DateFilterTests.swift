import XCTest
@testable import PurplePeek

/// The toolbar Date lens: window math + the two stored date dialects it must parse.
final class DateFilterTests: XCTestCase {

    func testAllHasNoCutoff() {
        XCTAssertNil(DateFilter.all.maxAge)
        XCTAssertNil(DateFilter.all.cutoff())
    }

    func testWindowLengths() {
        XCTAssertEqual(DateFilter.h1.maxAge, 3_600)
        XCTAssertEqual(DateFilter.h8.maxAge, 8 * 3_600)
        XCTAssertEqual(DateFilter.d1.maxAge, 86_400)
        XCTAssertEqual(DateFilter.d7.maxAge, 7 * 86_400)
        XCTAssertEqual(DateFilter.w2.maxAge, 14 * 86_400)
        XCTAssertEqual(DateFilter.m1.maxAge, 30 * 86_400)
    }

    func testCutoffIsNowMinusWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(DateFilter.h2.cutoff(now: now), now.addingTimeInterval(-7_200))
        XCTAssertEqual(DateFilter.d3.cutoff(now: now), now.addingTimeInterval(-3 * 86_400))
    }

    // MARK: MediaFile.modifiedDate — must accept both stored dialects

    private func file(modified: String?) -> MediaFile {
        MediaFile(id: "x", scanRoot: "/r", filePath: "/r/a.jpg", fileName: "a.jpg",
                  fileType: "photo", fileSize: 1, fileModifiedAt: modified,
                  keep: nil, isFavorite: false, isHidden: false, title: nil, caption: nil,
                  importedAt: nil, exportedAt: nil, deletedAt: nil, missingAt: nil,
                  contentHash: nil, photosAssetId: nil, createdAt: "", updatedAt: "")
    }

    func testParsesServerUTCFormat() {
        // PeekServer writes UTC with Z.
        let d = file(modified: "2026-06-15T18:51:32Z").modifiedDate
        XCTAssertNotNil(d)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(cal.component(.hour, from: d!), 18)
    }

    func testParsesLocalScannerFormat() {
        // The local scanner writes local time without a zone suffix.
        let d = file(modified: "2026-06-15T18:51:32").modifiedDate
        XCTAssertNotNil(d)
        XCTAssertEqual(Calendar.current.component(.hour, from: d!), 18)
    }

    func testAbsentOrGarbageDatesAreNil() {
        XCTAssertNil(file(modified: nil).modifiedDate)
        XCTAssertNil(file(modified: "").modifiedDate)
        XCTAssertNil(file(modified: "not a date").modifiedDate)
    }

    func testWindowMembership() {
        // An item modified 90 minutes ago passes 2h/1d windows but not 1h.
        let now = Date()
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        fmt.timeZone = TimeZone(identifier: "UTC")
        let f = file(modified: fmt.string(from: now.addingTimeInterval(-90 * 60)))
        let modified = f.modifiedDate!
        XCTAssertLessThan(modified, DateFilter.h1.cutoff(now: now)!)          // outside 1h
        XCTAssertGreaterThanOrEqual(modified, DateFilter.h2.cutoff(now: now)!) // inside 2h
        XCTAssertGreaterThanOrEqual(modified, DateFilter.d1.cutoff(now: now)!) // inside 1d
    }
}
