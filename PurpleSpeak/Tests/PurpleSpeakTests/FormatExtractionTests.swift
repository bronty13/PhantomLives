import Testing
import Foundation
@testable import PurpleSpeak

/// Hermetic round-trip tests for every import format PurpleSpeak claims to
/// support. Fixtures are committed under Tests/PurpleSpeakTests/Fixtures and
/// bundled via `resources: [.copy("Fixtures")]` in Package.swift, so these run
/// the REAL extraction code paths the app's import flow uses — on every machine,
/// no external setup.
@MainActor
struct FormatExtractionTests {

    static func fixture(_ name: String, _ ext: String) throws -> URL {
        try #require(
            Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"),
            "missing committed fixture \(name).\(ext)"
        )
    }

    @Test func pdfExtractsTextLayer() throws {
        let (title, text) = try TextExtractionService.extract(fileURL: Self.fixture("story", "pdf"))
        #expect(title == "story")
        #expect(text.contains("Lighthouse"))
        #expect(text.contains("spiral stairs"))
    }

    @Test func docxExtracts() throws {
        let (_, text) = try TextExtractionService.extract(fileURL: Self.fixture("story", "docx"))
        #expect(text.contains("Lighthouse"))
        #expect(text.contains("warning ships"))
    }

    @Test func rtfExtracts() throws {
        let (_, text) = try TextExtractionService.extract(fileURL: Self.fixture("story", "rtf"))
        #expect(text.contains("Lighthouse"))
    }

    @Test func epubExtractsSpineContent() throws {
        let (_, text) = try TextExtractionService.extract(fileURL: Self.fixture("story", "epub"))
        #expect(text.contains("first chapter"))
        #expect(text.contains("electronic book"))
    }

    @Test func htmlFileExtractsAllText() throws {
        // File-based HTML import keeps the whole document's text (tag-stripped).
        // Chrome removal is exclusive to the web-article URL path below.
        let (_, text) = try TextExtractionService.extract(fileURL: Self.fixture("article", "html"))
        #expect(text.contains("moon pulls the ocean"))
    }

    @Test func webArticleStripsChromeToArticleBody() async throws {
        // extractWebArticle runs the readability pass. A file:// URL lets us
        // exercise it hermetically (URLSession reads file URLs).
        let url = try Self.fixture("article", "html")
        let (title, text) = try await TextExtractionService.extractWebArticle(url)
        #expect(title.contains("Tides"))
        #expect(text.contains("moon pulls the ocean"))
        #expect(!text.contains("menu junk"))
        #expect(!text.contains("copyright junk"))
    }

    @Test func imageOCRReadsText() throws {
        let text = try OCRService.recognizeText(imageURL: Self.fixture("scan", "png"))
        #expect(text.lowercased().contains("reading printed text"))
    }

    @Test func unsupportedExtensionThrows() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("x.xyz")
        try? Data("hi".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: (any Error).self) {
            _ = try TextExtractionService.extract(fileURL: url)
        }
    }
}
