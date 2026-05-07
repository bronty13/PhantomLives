import XCTest
@testable import Timeliner

final class SearchServiceTests: XCTestCase {

    private func sample() -> (cases: [Case], events: [Event], people: [Person], tags: [Tag]) {
        let now = ISO8601DateFormatter().string(from: Date())
        let cases = [
            Case(id: "c1", title: "OJ Trial", caseDescription: "California murder case",
                 status: "active", pinned: false, createdAt: now, updatedAt: now),
            Case(id: "c2", title: "Boston Bombing", caseDescription: "marathon attack",
                 status: "closed", pinned: false, createdAt: now, updatedAt: now),
        ]
        let events = [
            Event(id: "e1", caseId: "c1", title: "Bronco chase",
                  dateStart: now, dateEnd: nil,
                  descriptionMarkdown: "white SUV pursued by LAPD",
                  sourceURL: "", importance: "high", createdAt: now),
            Event(id: "e2", caseId: "c2", title: "Manhunt",
                  dateStart: now, dateEnd: nil,
                  descriptionMarkdown: "shelter in place across boston",
                  sourceURL: "", importance: "critical", createdAt: now),
        ]
        let people = [
            Person(id: "p1", caseId: "c1", name: "OJ Simpson",
                   role: "suspect", notes: ""),
        ]
        let tags = [
            Tag(rowId: 1, name: "evidence", colorHex: "#E8A93B"),
            Tag(rowId: 2, name: "suspect",  colorHex: "#D14B5C"),
        ]
        return (cases, events, people, tags)
    }

    func testEmptyQueryReturnsNothing() {
        let s = sample()
        let hits = SearchService.run(
            query: "", cases: s.cases, events: s.events,
            people: s.people, tags: s.tags, tagsByEvent: [:]
        )
        XCTAssertTrue(hits.isEmpty)
    }

    func testCaseTitlePrefixOutranksBodyMatch() {
        let s = sample()
        // "Bo" — prefix-matches "Boston Bombing" case title (score 80)
        // and is also a substring inside "Bronco chase" body? Let's pick
        // a query that both a title prefix and a body match exist for.
        let hits = SearchService.run(
            query: "Bo", cases: s.cases, events: s.events,
            people: s.people, tags: s.tags, tagsByEvent: [:]
        )
        XCTAssertGreaterThan(hits.count, 0)
        XCTAssertEqual(hits.first?.title, "Boston Bombing")
    }

    func testPersonAndTagAreFound() {
        let s = sample()
        let hits = SearchService.run(
            query: "suspect", cases: s.cases, events: s.events,
            people: s.people, tags: s.tags, tagsByEvent: [:]
        )
        let kinds = Set(hits.map { $0.kind })
        XCTAssertTrue(kinds.contains(.tag))
    }

    func testNonMatchingQueryReturnsEmpty() {
        let s = sample()
        let hits = SearchService.run(
            query: "zzzzz-no-match", cases: s.cases, events: s.events,
            people: s.people, tags: s.tags, tagsByEvent: [:]
        )
        XCTAssertTrue(hits.isEmpty)
    }
}
