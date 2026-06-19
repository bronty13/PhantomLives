import Foundation
import Testing
@testable import Ircle

@Suite("Markdown parser")
struct MarkdownTests {

    @Test func headingsByLevel() {
        #expect(MarkdownParser.parse("# Title") == [.heading(level: 1, text: "Title")])
        #expect(MarkdownParser.parse("### Deep") == [.heading(level: 3, text: "Deep")])
    }

    @Test func consecutiveLinesFoldIntoOneParagraph() {
        #expect(MarkdownParser.parse("one\ntwo") == [.paragraph("one two")])
    }

    @Test func blankLineSeparatesParagraphs() {
        #expect(MarkdownParser.parse("a\n\nb") == [.paragraph("a"), .paragraph("b")])
    }

    @Test func bulletsNumberedAndQuotes() {
        #expect(MarkdownParser.parse("- a\n- b") == [.bullet("a"), .bullet("b")])
        #expect(MarkdownParser.parse("1. first\n2. second") == [.numbered("first"), .numbered("second")])
        #expect(MarkdownParser.parse("> hi") == [.quote("hi")])
    }

    @Test func fencedCodeBlock() {
        #expect(MarkdownParser.parse("```\nlet x = 1\nfoo()\n```") == [.code("let x = 1\nfoo()")])
    }

    @Test func horizontalRule() {
        #expect(MarkdownParser.parse("a\n\n---\n\nb") == [.paragraph("a"), .rule, .paragraph("b")])
    }

    @Test func indentedContinuationFoldsIntoBullet() {
        let out = MarkdownParser.parse("- The Channelbar\n  continues here")
        #expect(out == [.bullet("The Channelbar continues here")])
    }

    @Test func inlineMarkersArePreservedForLaterRendering() {
        #expect(MarkdownParser.parse("see **bold** and `code`") == [.paragraph("see **bold** and `code`")])
    }

    @Test func theBundledManualParsesIntoManyBlocks() {
        // Sanity: the actual manual text yields headings + content (when run
        // from the app bundle; in tests the resource may be absent, so guard).
        let blocks = MarkdownParser.parse(ManualView.manualText)
        #expect(!blocks.isEmpty)
        #expect(blocks.contains { if case .heading = $0 { return true } else { return false } })
    }
}
