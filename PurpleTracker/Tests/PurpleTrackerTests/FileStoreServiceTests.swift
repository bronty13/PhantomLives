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
        // Multiple bad chars collapse and trailing "-" is trimmed.
        XCTAssertEqual(FileStoreService.sanitize("foo/bar:baz?"), "foo-bar-baz")
        XCTAssertEqual(FileStoreService.sanitize("   "), "Untitled")
        XCTAssertEqual(FileStoreService.sanitize(""), "Untitled")
    }

    func testSanitizeStripsControlAndAllReservedChars() {
        // Every Windows-reserved + control char must be replaced.
        let nasty = "a\u{0000}b\u{0007}c\u{001F}d\u{007F}e<f>g|h*i\"j\\k"
        let out = FileStoreService.sanitize(nasty)
        XCTAssertFalse(out.contains("\u{0000}"))
        XCTAssertFalse(out.contains("<"))
        XCTAssertFalse(out.contains(">"))
        XCTAssertFalse(out.contains("|"))
        XCTAssertFalse(out.contains("*"))
        XCTAssertFalse(out.contains("\""))
        XCTAssertFalse(out.contains("\\"))
        XCTAssertEqual(out, "a-b-c-d-e-f-g-h-i-j-k")
    }

    func testSanitizeTrimsLeadingTrailingDotsAndSpaces() {
        XCTAssertEqual(FileStoreService.sanitize("  ..hello..  "), "hello")
        XCTAssertEqual(FileStoreService.sanitize("..."), "Untitled")
    }

    func testSanitizeEscapesWindowsReservedNames() {
        XCTAssertEqual(FileStoreService.sanitize("CON"), "CON_")
        XCTAssertEqual(FileStoreService.sanitize("nul"), "nul_")
        XCTAssertEqual(FileStoreService.sanitize("LPT3"), "LPT3_")
        // Non-reserved names with a similar prefix are untouched.
        XCTAssertEqual(FileStoreService.sanitize("CONference"), "CONference")
    }

    func testSanitizeCapsAtMaxBytes() {
        let long = String(repeating: "x", count: 400)
        let out = FileStoreService.sanitize(long)
        XCTAssertLessThanOrEqual(out.utf8.count, 200)
    }
}
