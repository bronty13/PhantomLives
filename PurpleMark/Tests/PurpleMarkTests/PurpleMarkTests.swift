import XCTest
@testable import PurpleMark
import PurpleMarkRenderCore

final class OutlineParserTests: XCTestCase {
    func testParsesHeadingsWithLevels() {
        let md = """
        # Title
        intro
        ## Section A
        ### Sub
        ## Section B
        """
        let items = OutlineParser.outline(from: md)
        XCTAssertEqual(items.map(\.level), [1, 2, 3, 2])
        XCTAssertEqual(items.map(\.title), ["Title", "Section A", "Sub", "Section B"])
        XCTAssertEqual(items.first?.line, 0)
    }

    func testSkipsHeadingsInsideFencedCode() {
        let md = """
        # Real
        ```
        # not a heading
        ```
        ## Also Real
        """
        let items = OutlineParser.outline(from: md)
        XCTAssertEqual(items.map(\.title), ["Real", "Also Real"])
    }

    func testIgnoresNonHeadingHashes() {
        let items = OutlineParser.outline(from: "#nospace\nplain #tag here")
        XCTAssertTrue(items.isEmpty)
    }

    func testStatsCounts() {
        let s = OutlineParser.stats(from: "one two three\nfour")
        XCTAssertEqual(s.words, 4)
        XCTAssertEqual(s.lines, 2)
        XCTAssertEqual(s.characters, "one two three\nfour".count)
        XCTAssertEqual(s.readMinutes, 1)
    }

    func testEmptyStats() {
        let s = OutlineParser.stats(from: "")
        XCTAssertEqual(s.words, 0)
        XCTAssertEqual(s.lines, 0)
        XCTAssertEqual(s.readMinutes, 0)
    }
}

final class RenderCoreTests: XCTestCase {
    func testStandaloneHTMLEmbedsMarkdownAndLibraries() {
        let html = RenderCore.standaloneHTML(markdown: "# Hello PurpleMark", theme: .nord, width: .wide)
        XCTAssertTrue(html.contains("# Hello PurpleMark"), "markdown should be embedded")
        XCTAssertTrue(html.contains("theme-nord"), "theme class should be applied")
        XCTAssertTrue(html.contains("width-wide"), "reading-width class should be applied")
        XCTAssertTrue(html.contains("markdownit"), "markdown-it should be inlined")
        XCTAssertTrue(html.contains("mermaid"), "mermaid should be inlined")
        XCTAssertTrue(html.lowercased().contains("katex"), "KaTeX should be inlined")
    }

    func testStandaloneHTMLInlinesFonts() {
        let html = RenderCore.standaloneHTML(markdown: "x", theme: .default, width: .default)
        XCTAssertTrue(html.contains("data:font/woff2;base64,"),
                      "KaTeX fonts should be base64-inlined for offline rendering")
    }

    func testJSStringLiteralEscapes() {
        let lit = RenderCore.jsStringLiteral("a\"b\nc")
        XCTAssertTrue(lit.hasPrefix("\""))
        XCTAssertTrue(lit.contains("\\\""))
        XCTAssertTrue(lit.contains("\\n"))
    }

    func testWebResourcesPresent() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: RenderCore.indexURL.path),
                      "index.html should ship in the framework bundle")
    }
}

final class MarkdownThumbnailTests: XCTestCase {
    func testPreviewLinesClassifyAndStrip() {
        let md = """
        # Title
        Some **bold** body.
        - first
        1. second
        > a quote
        ```swift
        let x = 1
        ```
        """
        let lines = MarkdownThumbnail.previewLines(from: md, max: 16)
        XCTAssertEqual(lines[0], .init(kind: .h1, text: "Title"))
        XCTAssertEqual(lines[1], .init(kind: .normal, text: "Some bold body."))
        XCTAssertEqual(lines[2], .init(kind: .bullet, text: "first"))
        XCTAssertEqual(lines[3], .init(kind: .bullet, text: "second"))
        XCTAssertEqual(lines[4], .init(kind: .quote, text: "a quote"))
        XCTAssertEqual(lines[5].kind, .code)            // fence opener (info "swift")
        XCTAssertTrue(lines.contains(.init(kind: .code, text: "let x = 1")))
    }

    func testPreviewLinesRespectsMax() {
        let md = (1...50).map { "line \($0)" }.joined(separator: "\n")
        XCTAssertEqual(MarkdownThumbnail.previewLines(from: md, max: 5).count, 5)
    }

    func testPreviewSkipsLeadingBlankLines() {
        let lines = MarkdownThumbnail.previewLines(from: "\n\n\n# Heading", max: 8)
        XCTAssertEqual(lines.first?.kind, .h1)
    }

    @MainActor
    func testDrawRendersNonEmptyImage() throws {
        let size = CGSize(width: 480, height: 620)
        let image = NSImage(size: size)
        image.lockFocus()
        MarkdownThumbnail.draw(markdown: """
        # PurpleMark Demo

        A quick check of the renderer.
        - First item
        - Second item
        > A blockquote.
        ## Section
        Body paragraph here.
        """, size: size)
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        // Side-effect for manual inspection during development.
        try? png.write(to: URL(fileURLWithPath: "/tmp/pm-thumb-render.png"))
        XCTAssertGreaterThan(png.count, 2000, "thumbnail should produce a non-trivial image")
    }
}

final class BackupServiceTests: XCTestCase {
    @MainActor
    func testRunBackupCreatesArchive() throws {
        let fm = FileManager.default
        let support = fm.temporaryDirectory.appendingPathComponent("pm-support-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        try "hello".write(to: support.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
        let backupDir = fm.temporaryDirectory.appendingPathComponent("pm-backups-\(UUID())", isDirectory: true)
        defer { try? fm.removeItem(at: support); try? fm.removeItem(at: backupDir) }

        let url = try BackupService.runBackup(supportDir: support, backupDir: backupDir)
        XCTAssertTrue(fm.fileExists(atPath: url.path))
        XCTAssertTrue(url.lastPathComponent.hasPrefix("PurpleMark-"))
        XCTAssertEqual(url.pathExtension, "zip")

        let listed = BackupService.listBackups(in: backupDir)
        XCTAssertEqual(listed.count, 1)
    }

    @MainActor
    func testTrimRespectsRetention() throws {
        let fm = FileManager.default
        let backupDir = fm.temporaryDirectory.appendingPathComponent("pm-trim-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: backupDir) }

        // An "old" archive (modified 30 days ago) gets trimmed at 14-day retention.
        let old = backupDir.appendingPathComponent("PurpleMark-2000-01-01-000000.zip")
        try Data([0x50, 0x4b]).write(to: old)
        let past = Date().addingTimeInterval(-30 * 86400)
        try fm.setAttributes([.modificationDate: past], ofItemAtPath: old.path)

        let removed = BackupService.trimOldBackups(in: backupDir, retentionDays: 14)
        XCTAssertEqual(removed, 1)
        XCTAssertFalse(fm.fileExists(atPath: old.path))
    }
}

final class ExportServiceTests: XCTestCase {
    @MainActor
    func testExportHTMLWritesSelfContainedFile() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("pm-export-\(UUID())", isDirectory: true)
        defer { try? fm.removeItem(at: dir) }

        let url = try ExportService.shared.exportHTML(
            markdown: "# Exported\n\nBody text.",
            baseName: "Notes.md", theme: .default, width: .default, to: dir)

        XCTAssertEqual(url.pathExtension, "html")
        XCTAssertEqual(url.lastPathComponent, "Notes.html")
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("# Exported"))
        XCTAssertTrue(contents.contains("data:font/woff2;base64,"))
    }
}

final class AppSettingsTests: XCTestCase {
    @MainActor
    func testTypedAccessorsRoundTrip() {
        let s = AppSettings()
        s.theme = .solarized
        XCTAssertEqual(s.theme, .solarized)
        XCTAssertEqual(s.themeRaw, "solarized")
        s.defaultView = .markdown
        XCTAssertEqual(s.defaultView, .markdown)
        s.readingWidth = .full
        XCTAssertEqual(s.readingWidth, .full)
    }

    @MainActor
    func testExportDirectoryDefaultsToDownloads() {
        let s = AppSettings()
        s.exportDirectoryPath = ""
        XCTAssertTrue(s.exportDirectory.path.contains("Downloads/PurpleMark"))
    }
}

final class FileServiceTests: XCTestCase {
    func testMarkdownFilesFiltersAndSorts() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("pm-files-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        for name in ["b.md", "a.markdown", "ignore.png", "c.txt"] {
            try "x".write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let files = FileService.markdownFiles(in: dir).map(\.lastPathComponent)
        XCTAssertEqual(files, ["a.markdown", "b.md", "c.txt"])
        XCTAssertFalse(files.contains("ignore.png"))
    }
}
