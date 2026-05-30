import XCTest
@testable import PurpleDiary

final class SearchServiceTests: XCTestCase {

    private func entry(_ id: String, title: String, body: String = "", daysAgo: Int = 0) -> Entry {
        var e = Entry.newDraft(date: Date().addingTimeInterval(-Double(daysAgo) * 86400), title: title)
        e.id = id
        e.bodyMarkdown = body
        return e
    }

    func testEmptyQueryReturnsAllNewestFirst() {
        let entries = [
            entry("a", title: "Old", daysAgo: 10),
            entry("b", title: "New", daysAgo: 1),
        ]
        let results = SearchService.search("", in: entries)
        XCTAssertEqual(results.map(\.entry.id), ["b", "a"])
    }

    func testTitlePrefixOutranksBodyMatch() {
        let entries = [
            entry("body", title: "Random", body: "a walk by the water"),
            entry("prefix", title: "Walk in the park"),
        ]
        let results = SearchService.search("walk", in: entries)
        XCTAssertEqual(results.first?.entry.id, "prefix",
                       "Title-prefix match should outrank a body match")
    }

    func testTagMatchIsFound() {
        let entries = [entry("x", title: "Nothing relevant")]
        let tagsByEntry = ["x": [Tag(rowId: 1, name: "gratitude", colorHex: "#000000")]]
        let results = SearchService.search("grat", in: entries, tagsByEntry: tagsByEntry)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.entry.id, "x")
    }

    func testNoMatchReturnsEmpty() {
        let entries = [entry("x", title: "Apples", body: "oranges")]
        XCTAssertTrue(SearchService.search("zebra", in: entries).isEmpty)
    }
}
