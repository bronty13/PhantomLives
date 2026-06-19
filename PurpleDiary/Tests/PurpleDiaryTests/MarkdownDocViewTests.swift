import XCTest
@testable import PurpleDiary

/// Unit-tests the small hand-rolled markdown parser in `MarkdownDocView` (the
/// in-app reader for both `Docs/SECURITY.md` and `USER_MANUAL.md`). The view
/// itself is SwiftUI and verified by hand; the parser is pure and worth locking
/// down so a future "let's switch to a real markdown library" change doesn't
/// silently lose constructs the docs use.
final class MarkdownDocViewTests: XCTestCase {

    func testHeadingsAtAllThreeLevels() {
        let md = """
        # Top
        ## Sub
        ### Subsub
        """
        let blocks = MarkdownDocView.parse(md)
        XCTAssertEqual(blocks.count, 3)
        if case .h1(let s) = blocks[0] { XCTAssertEqual(s, "Top") } else { XCTFail("first block should be h1") }
        if case .h2(let s) = blocks[1] { XCTAssertEqual(s, "Sub") } else { XCTFail("second block should be h2") }
        if case .h3(let s) = blocks[2] { XCTAssertEqual(s, "Subsub") } else { XCTFail("third block should be h3") }
    }

    func testBulletAndDashListItems() {
        let md = """
        - first
        * second
        """
        let blocks = MarkdownDocView.parse(md)
        XCTAssertEqual(blocks.count, 2)
        for block in blocks {
            if case .listItem = block { continue }
            XCTFail("each line should parse as a list item, got \(block)")
        }
    }

    func testNumberedItemRetainsNumber() {
        let md = "1. First step\n2. Second step"
        let blocks = MarkdownDocView.parse(md)
        XCTAssertEqual(blocks.count, 2)
        if case .numberedItem(let n, _) = blocks[0] { XCTAssertEqual(n, 1) } else { XCTFail("first should be numberedItem") }
        if case .numberedItem(let n, _) = blocks[1] { XCTAssertEqual(n, 2) } else { XCTFail("second should be numberedItem") }
    }

    func testDividerOnTripleDash() {
        let blocks = MarkdownDocView.parse("First\n\n---\n\nSecond")
        XCTAssertEqual(blocks.count, 3)
        if case .divider = blocks[1] { } else { XCTFail("middle block should be divider") }
    }

    func testFencedCodeBlockIsPreservedVerbatim() {
        let md = """
        Some prose.

        ```
        PRAGMA key = 'x''deadbeef'''
        PRAGMA cipher_page_size = 4096
        ```
        """
        let blocks = MarkdownDocView.parse(md)
        XCTAssertEqual(blocks.count, 2)
        if case .codeBlock(let s) = blocks[1] {
            XCTAssertTrue(s.contains("PRAGMA key"))
            XCTAssertTrue(s.contains("cipher_page_size = 4096"))
        } else {
            XCTFail("second block should be a code block")
        }
    }

    func testParagraphsJoinConsecutiveLines() {
        let blocks = MarkdownDocView.parse("Line one\nLine two\n\nNext paragraph")
        XCTAssertEqual(blocks.count, 2)
        if case .paragraph(let attr) = blocks[0] {
            XCTAssertEqual(String(attr.characters), "Line one Line two")
        } else { XCTFail() }
        if case .paragraph(let attr) = blocks[1] {
            XCTAssertEqual(String(attr.characters), "Next paragraph")
        } else { XCTFail() }
    }

    func testBundledSecurityMdLoadsAndParses() throws {
        // Sanity check that the build wired Docs/SECURITY.md into the app
        // bundle. If this fails under a real app run, project.yml's
        // `Docs/SECURITY.md` entry got dropped or its destination changed.
        let blocks = try parseBundled("SECURITY")
        XCTAssertGreaterThan(blocks.count, 20, "Whitepaper should parse into many blocks")
        if case .h1(let s) = blocks.first {
            XCTAssertTrue(s.lowercased().contains("security"))
        } else {
            XCTFail("First block should be the H1 title")
        }
    }

    func testBundledUserManualMdLoadsAndParses() throws {
        // The user manual is also bundled (Help → PurpleDiary User Manual). If
        // this fails, project.yml's `USER_MANUAL.md` resource entry got dropped.
        let blocks = try parseBundled("USER_MANUAL")
        XCTAssertGreaterThan(blocks.count, 20, "User manual should parse into many blocks")
        if case .h1(let s) = blocks.first {
            XCTAssertTrue(s.lowercased().contains("manual"))
        } else {
            XCTFail("First block should be the H1 title")
        }
    }

    /// Loads a bundled `<name>.md` from the app or test-host bundle and parses
    /// it; skips under SwiftPM-only runs where resources aren't copied.
    private func parseBundled(_ name: String) throws -> [MarkdownDocView.Block] {
        let bundle = Bundle(for: type(of: self))
        let candidate =
            Bundle.main.url(forResource: name, withExtension: "md") ??
            bundle.url(forResource: name, withExtension: "md")
        guard let url = candidate else {
            throw XCTSkip("\(name).md not found in any test-host bundle; this is fine under SwiftPM-only runs.")
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return MarkdownDocView.parse(text)
    }
}
