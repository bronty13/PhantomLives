import XCTest
@testable import PurpleTracker

final class URLAutofillServiceTests: XCTestCase {
    func testDetectsServiceNowIncidentURL() {
        let m = URLAutofillService.detect(
            "https://defi.service-now.com/now/nav/ui/classic/params/target/incident.do%3Fsys_id%3Dabc%26number%3DINC0012345"
        )
        XCTAssertEqual(m, .snow(number: "INC0012345"))
    }

    func testDetectsServiceNowVariantPrefixes() {
        XCTAssertEqual(URLAutofillService.detect("https://defi.service-now.com/?id=ritm&number=RITM0001234"),
                       .snow(number: "RITM0001234"))
        XCTAssertEqual(URLAutofillService.detect("https://defi.service-now.com/?id=task_view&number=TASK0007890"),
                       .snow(number: "TASK0007890"))
    }

    func testDetectsAzureDevOpsWorkItemURL() {
        XCTAssertEqual(
            URLAutofillService.detect("https://dev.azure.com/org/proj/_workitems/edit/12345"),
            .ado(number: "12345")
        )
    }

    func testReturnsNilForUnrelatedURL() {
        XCTAssertNil(URLAutofillService.detect("https://example.com/whatever"))
    }
}

final class EmailParserTests: XCTestCase {
    func testParsesBasicEml() {
        let raw = """
        From: alice@example.com
        Subject: Hello world
        Date: Mon, 11 Apr 2026 10:00:00 +0000
        To: bob@example.com

        This is the body.
        Multi-line.
        """
        let p = EmailParser.parse(raw)
        XCTAssertEqual(p.from, "alice@example.com")
        XCTAssertEqual(p.subject, "Hello world")
        XCTAssertNotNil(p.date)
        XCTAssertTrue(p.body.contains("This is the body."))
        XCTAssertTrue(p.body.contains("Multi-line."))
    }

    func testHandlesFoldedHeaders() {
        let raw = """
        Subject: Long
         folded subject
        From: a@b.com

        body
        """
        let p = EmailParser.parse(raw)
        XCTAssertEqual(p.subject, "Long folded subject")
    }
}

final class ICSExporterTests: XCTestCase {
    @MainActor
    func testRendersVeventForOpenMatterWithDueDate() {
        var m = makeMatter()
        m.dueAt = Date(timeIntervalSince1970: 1_700_000_000)
        m.status = "New"
        let ics = ICSExporter.render(matters: [m], statusValues: [("New", 0), ("Closed", 1)])
        XCTAssertTrue(ics.contains("BEGIN:VEVENT"))
        XCTAssertTrue(ics.contains("UID:purpletracker-\(m.id)@local"))
        XCTAssertTrue(ics.contains("SUMMARY:\(m.id) — \(m.title)"))
    }

    @MainActor
    func testSkipsClosedAndDeletedMatters() {
        var open = makeMatter(); open.dueAt = Date(); open.status = "New"
        var closed = makeMatter(); closed.dueAt = Date(); closed.status = "Closed"
        var trashed = makeMatter(); trashed.dueAt = Date(); trashed.status = "New"
        trashed.deletedAt = Date()
        let ics = ICSExporter.render(matters: [open, closed, trashed],
                                     statusValues: [("New", 0), ("Closed", 1)])
        XCTAssertEqual(ics.components(separatedBy: "BEGIN:VEVENT").count - 1, 1)
    }

    private func makeMatter() -> Matter {
        Matter.newDraft(id: "2026-01-01-00001", typeId: "t1", title: "T")
    }
}

final class TimeByTagReportTests: XCTestCase {
    func testEvenSplitAcrossInitiatives() {
        let m = Matter.newDraft(id: "2026-01-01-00001", typeId: "t", title: "x")
        let entry = TimeEntry(id: "e1", matterId: m.id,
                              startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                              endedAt:   Date(timeIntervalSince1970: 1_700_003_600),
                              seconds: 3600, note: "")
        let inits = [Initiative(id: "i1", name: "Alpha", sortOrder: 0),
                     Initiative(id: "i2", name: "Beta",  sortOrder: 1)]
        let md = TimeByTagReport.render(
            group: .initiative,
            matters: [m],
            entries: [entry],
            initiatives: inits,
            goals: [],
            matterInitiativeIds: [m.id: ["i1", "i2"]],
            matterGoalIds: [:]
        )
        XCTAssertTrue(md.contains("| Alpha | 0.50 |"))
        XCTAssertTrue(md.contains("| Beta | 0.50 |"))
    }
}
