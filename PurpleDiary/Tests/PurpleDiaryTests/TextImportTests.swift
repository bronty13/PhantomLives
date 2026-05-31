import XCTest
import AppKit
@testable import PurpleDiary

/// Covers importing a text file's contents into an entry body: the pure
/// smart-merge rule and reading Markdown / plain-text / RTF files off disk.
@MainActor
final class TextImportTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("pd-textimport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: - mergedBody

    func testMergeIntoEmptyBodyBecomesTheBody() {
        XCTAssertEqual(TextImportService.mergedBody(existing: "", imported: "Hello"), "Hello")
        XCTAssertEqual(TextImportService.mergedBody(existing: "   \n ", imported: "Hello"), "Hello")
    }

    func testMergeIntoNonEmptyBodyAppendsWithSeparator() {
        let merged = TextImportService.mergedBody(existing: "First line", imported: "Imported text")
        XCTAssertEqual(merged, "First line\n\n---\n\nImported text")
    }

    func testMergeTrimsSurroundingWhitespace() {
        let merged = TextImportService.mergedBody(existing: "  Body  ", imported: "\n\nImported\n\n")
        XCTAssertEqual(merged, "Body\n\n---\n\nImported")
    }

    func testMergeWithEmptyImportLeavesBodyUnchanged() {
        XCTAssertEqual(TextImportService.mergedBody(existing: "Keep me", imported: "   \n\t"), "Keep me")
    }

    // MARK: - readText

    func testReadsMarkdownAndPlainText() throws {
        let md = scratch.appendingPathComponent("note.md")
        try "# Title\n\nSome **bold** body.".write(to: md, atomically: true, encoding: .utf8)
        XCTAssertEqual(TextImportService.readText(from: md), "# Title\n\nSome **bold** body.")

        let txt = scratch.appendingPathComponent("plain.txt")
        try "just text".write(to: txt, atomically: true, encoding: .utf8)
        XCTAssertEqual(TextImportService.readText(from: txt), "just text")
    }

    func testReadsRTFAsPlainString() throws {
        let attr = NSAttributedString(string: "rich text content")
        let data = try XCTUnwrap(attr.rtf(from: NSRange(location: 0, length: attr.length),
                                          documentAttributes: [:]))
        let rtf = scratch.appendingPathComponent("doc.rtf")
        try data.write(to: rtf)
        XCTAssertEqual(TextImportService.readText(from: rtf), "rich text content")
    }
}
