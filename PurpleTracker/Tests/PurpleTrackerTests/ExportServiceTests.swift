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
            cadenceId: nil, parentMatterId: nil,
            requestorAssociateId: "",
            interestedParty1AssociateId: "", interestedParty2AssociateId: "",
            interestedParty3AssociateId: "", interestedParty4AssociateId: "",
            interestedParty5AssociateId: "",
            externalInterestedParty1: "", externalInterestedParty2: "",
            externalInterestedParty3: "", externalInterestedParty4: "",
            externalInterestedParty5: ""
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

    @MainActor
    func testMarkdownIncludesInterestedPartiesAndExternals() {
        // External IPs are pure text and must always appear when populated.
        // Internal IPs / Requestor reference person rows that don't exist in
        // this test DB, so they should be silently omitted (no crash).
        var m = sampleMatter()
        m.requestorAssociateId = "AID-NOT-IN-DB"
        m.interestedParty1AssociateId = "AID-IP1"
        m.externalInterestedParty1 = "Acme Corp – Jane Roe"
        m.externalInterestedParty3 = "Big Bank – auditor"

        let type = MatterType(id: "t1", name: "Client Request", colorHex: "#000",
                              sortOrder: 0, isCadenced: false)
        let md = ExportService.renderMarkdown(
            matter: m, types: [type], notes: [], timeEntries: [], attachments: [],
            settings: AppSettings()
        )

        XCTAssertTrue(md.contains("**External Interested Parties:**"),
                      "External IP heading must appear when any external IP is set")
        XCTAssertTrue(md.contains("Acme Corp – Jane Roe"),
                      "External IP 1 text must be exported")
        XCTAssertTrue(md.contains("Big Bank – auditor"),
                      "External IP 3 text must be exported")
        XCTAssertTrue(md.contains("**Status:**"))
    }
}
