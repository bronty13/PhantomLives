import XCTest
@testable import PurpleTracker

final class ExportServiceTests: XCTestCase {

    private func sampleMatter() -> Matter {
        let cal = Calendar(identifier: .gregorian)
        let opened = cal.date(from: DateComponents(year: 2026, month: 5, day: 7, hour: 9))!
        return Matter(
            id: "2026-05-07-00001", title: "Test Matter",
            typeId: "t1", status: "In-Progress",
            descriptionMd: "## Hello\nbody", dueAt: opened,
            createdAt: opened, accessedAt: opened, modifiedAt: opened,
            external1Number: "INC-1", external1Url: "https://snow.example/INC-1",
            external2Number: "", external2Url: "",
            external3Number: "", external3Url: "",
            timeTrackingCode: "BU-7",
            resolutionMd: "Done.", lessonsMd: "", notesMd: "",
            fileStorePrimary: "/tmp/p", fileStoreSecondary: "/tmp/s",
            cadenceId: nil, parentMatterId: nil
        )
    }

    @MainActor
    func testBriefFormat() {
        let m = sampleMatter()
        let b = ExportService.brief(m)
        XCTAssertTrue(b.hasPrefix("2026-05-07-00001 • Test Matter • "), b)
        XCTAssertTrue(b.hasSuffix("• In-Progress"), b)
    }

    @MainActor
    func testMarkdownIncludesAllSections() {
        let m = sampleMatter()
        let type = MatterType(id: "t1", name: "Client Request", colorHex: "#000", sortOrder: 0, isCadenced: false)
        let md = ExportService.renderMarkdown(
            matter: m, types: [type], notes: [], timeEntries: [], attachments: [], settings: AppSettings()
        )
        XCTAssertTrue(md.contains("# Test Matter"))
        XCTAssertTrue(md.contains("**Matter ID:** `2026-05-07-00001`"))
        XCTAssertTrue(md.contains("**Type:** Client Request"))
        XCTAssertTrue(md.contains("**Status:** In-Progress"))
        XCTAssertTrue(md.contains("## Description"))
        XCTAssertTrue(md.contains("## Resolution"))
        XCTAssertTrue(md.contains("defi SUPPORT (SNOW)"))
    }
}
