import XCTest
@testable import PurpleTracker

@MainActor
final class FileStoreServiceTests: XCTestCase {
    func testTemplateSubstitution() {
        let cal = Calendar(identifier: .gregorian)
        let date = cal.date(from: DateComponents(year: 2026, month: 5, day: 7))!
        let tmpl = "~/Library/CloudStorage/OneDrive-defiSOLUTIONS/{year}/{date} {title}"
        let out = FileStoreService.render(template: tmpl, title: "Q2 SOC Review", date: date)
        XCTAssertEqual(out, "~/Library/CloudStorage/OneDrive-defiSOLUTIONS/2026/2026-05-07 Q2 SOC Review")
    }

    func testTemplateUsesMatterIdDate() {
        let tmpl = "{date}/{title}"
        let out = FileStoreService.render(template: tmpl, title: "X", matterId: "2025-12-31-00042")
        XCTAssertEqual(out, "2025-12-31/X")
    }

    func testSanitizeStripsBadCharsAndFallsBackToUntitled() {
        XCTAssertEqual(FileStoreService.sanitize("foo/bar:baz?"), "foo-bar-baz-")
        XCTAssertEqual(FileStoreService.sanitize("   "), "Untitled")
        XCTAssertEqual(FileStoreService.sanitize(""), "Untitled")
    }
}
