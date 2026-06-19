import XCTest
@testable import PurpleDiary

/// The pure string transforms behind the editor's format toolbar
/// (`MarkdownFormat`). The toolbar's `NSTextView` plumbing is verified by hand;
/// this locks down the substitution logic, which is the off-by-one-prone part.
final class MarkdownFormatTests: XCTestCase {

    // MARK: wrap

    func testWrapWrapsSelection() {
        XCTAssertEqual(MarkdownFormat.wrapped("bold", marker: "**"), "**bold**")
        XCTAssertEqual(MarkdownFormat.wrapped("x", marker: "~~"), "~~x~~")
    }

    func testWrapEmptySelectionMakesEmptyMarkers() {
        // Used when the cursor has no selection — the action then drops the cursor
        // between the markers.
        XCTAssertEqual(MarkdownFormat.wrapped("", marker: "*"), "**")
    }

    // MARK: linePrefix

    func testLinePrefixSingleLine() {
        XCTAssertEqual(MarkdownFormat.linePrefixed("Title", marker: "## "), "## Title")
    }

    func testLinePrefixEveryLineInABlock() {
        let block = "milk\neggs\nbread"
        XCTAssertEqual(MarkdownFormat.linePrefixed(block, marker: "- "),
                       "- milk\n- eggs\n- bread")
    }

    func testLinePrefixLeavesTrailingEmptyLineAlone() {
        // A selection that includes the trailing newline yields a final "" line;
        // it must NOT get a dangling prefix.
        XCTAssertEqual(MarkdownFormat.linePrefixed("a\nb\n", marker: "> "),
                       "> a\n> b\n")
    }

    func testLinePrefixChecklist() {
        XCTAssertEqual(MarkdownFormat.linePrefixed("todo", marker: "- [ ] "), "- [ ] todo")
    }

    // MARK: clear

    func testClearStripsInlineMarkers() {
        XCTAssertEqual(MarkdownFormat.cleared("**bold** and *italic* and ~~gone~~ and `code`"),
                       "bold and italic and gone and code")
    }

    func testClearStripsLineMarkers() {
        XCTAssertEqual(MarkdownFormat.cleared("## Heading"), "Heading")
        XCTAssertEqual(MarkdownFormat.cleared("- bullet"), "bullet")
        XCTAssertEqual(MarkdownFormat.cleared("1. numbered"), "numbered")
        XCTAssertEqual(MarkdownFormat.cleared("> quote"), "quote")
        XCTAssertEqual(MarkdownFormat.cleared("- [ ] task"), "task")
        XCTAssertEqual(MarkdownFormat.cleared("- [x] done"), "done")
    }

    func testClearAcrossMultipleLines() {
        XCTAssertEqual(MarkdownFormat.cleared("# Title\n- **a**\n- *b*"),
                       "Title\na\nb")
    }

    func testClearIsNoOpOnPlainText() {
        XCTAssertEqual(MarkdownFormat.cleared("just words here"), "just words here")
    }
}
