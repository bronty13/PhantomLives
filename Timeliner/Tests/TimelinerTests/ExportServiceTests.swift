import XCTest
@testable import Timeliner

final class ExportServiceTests: XCTestCase {

    @MainActor
    func testRenderProducesSelfContainedHTML() {
        let now = ISO8601DateFormatter().string(from: Date())
        let aCase = Case(
            id: "C", title: "Sample Case",
            caseDescription: "A short **bold** intro.",
            status: "active", pinned: false,
            createdAt: now, updatedAt: now
        )
        let events = [
            Event(id: "E1", caseId: "C", title: "First event",
                  dateStart: "2026-01-15T08:00:00Z", dateEnd: nil,
                  descriptionMarkdown: "An *italic* description.",
                  sourceURL: "https://example.com",
                  importance: "high", createdAt: now)
        ]
        let people = [
            Person(id: "P1", caseId: "C", name: "Jane Doe",
                   role: "witness", notes: "Saw the car.")
        ]
        let tags: [Tag] = []
        let html = ExportService.render(
            aCase: aCase,
            events: events,
            people: people,
            tagsByEvent: ["E1": tags],
            peopleByEvent: ["E1": people]
        )

        XCTAssertTrue(html.hasPrefix("<!doctype html>"),
                      "Export should be a complete HTML document")
        XCTAssertTrue(html.contains("Sample Case"))
        XCTAssertTrue(html.contains("First event"))
        XCTAssertTrue(html.contains("Jane Doe"))
        XCTAssertTrue(html.contains("<style>"), "Should embed CSS inline")
        XCTAssertTrue(html.contains("<script>"), "Should embed JS inline")
        XCTAssertFalse(html.contains("http://"), "No external URLs in CSS/JS")
        XCTAssertTrue(html.contains("<strong>bold</strong>"),
                      "Inline markdown bold should render")
    }

    @MainActor
    func testHTMLEscapesUserContent() {
        let now = ISO8601DateFormatter().string(from: Date())
        let aCase = Case(
            id: "C", title: "<script>alert(1)</script>",
            caseDescription: "",
            status: "active", pinned: false,
            createdAt: now, updatedAt: now
        )
        let html = ExportService.render(
            aCase: aCase,
            events: [],
            people: [],
            tagsByEvent: [:],
            peopleByEvent: [:]
        )
        XCTAssertFalse(html.contains("<script>alert(1)</script>"),
                       "User-provided HTML must be escaped before embedding")
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
    }
}
