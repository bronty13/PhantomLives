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
        let html = RenderCore.standaloneHTML(markdown: "# Hello PurpleMark",
                                             colors: .builtin(.nord), width: .wide)
        XCTAssertTrue(html.contains("# Hello PurpleMark"), "markdown should be embedded")
        XCTAssertTrue(html.contains("#2e3440"), "the Nord background should be inlined on the body")
        XCTAssertTrue(html.contains("width-wide"), "reading-width class should be applied")
        XCTAssertTrue(html.contains("markdownit"), "markdown-it should be inlined")
        XCTAssertTrue(html.contains("mermaid"), "mermaid should be inlined")
        XCTAssertTrue(html.lowercased().contains("katex"), "KaTeX should be inlined")
    }

    func testStandaloneHTMLInlinesFonts() {
        let html = RenderCore.standaloneHTML(markdown: "x", colors: .builtin(.default), width: .default)
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
            baseName: "Notes.md", colors: .builtin(.default), width: .default, to: dir)

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

final class FindControllerTests: XCTestCase {
    @MainActor
    func testLiteralCaseInsensitiveByDefault() {
        let ranges = FindController.findMatches(query: "the", in: "The theme is theirs.",
                                                regex: false, caseSensitive: false)
        XCTAssertEqual(ranges.count, 3)
        XCTAssertEqual(ranges.first, NSRange(location: 0, length: 3))
    }

    @MainActor
    func testLiteralCaseSensitive() {
        let ranges = FindController.findMatches(query: "the", in: "The theme is theirs.",
                                                regex: false, caseSensitive: true)
        XCTAssertEqual(ranges.count, 2) // "The" excluded
    }

    @MainActor
    func testRegexMatches() {
        let ranges = FindController.findMatches(query: #"\d+"#, in: "a1 b22 c333",
                                                regex: true, caseSensitive: false)
        XCTAssertEqual(ranges.map(\.length), [1, 2, 3])
    }

    @MainActor
    func testInvalidRegexYieldsNoMatches() {
        let ranges = FindController.findMatches(query: "(", in: "((((", regex: true, caseSensitive: false)
        XCTAssertTrue(ranges.isEmpty)
    }

    @MainActor
    func testEmptyQueryAndNoMatch() {
        XCTAssertTrue(FindController.findMatches(query: "", in: "abc", regex: false, caseSensitive: false).isEmpty)
        XCTAssertTrue(FindController.findMatches(query: "zzz", in: "abc", regex: false, caseSensitive: false).isEmpty)
    }

    @MainActor
    func testOverlappingLiteralAdvancesPastEachMatch() {
        // "aa" in "aaaa" → non-overlapping matches at 0 and 2.
        let ranges = FindController.findMatches(query: "aa", in: "aaaa", regex: false, caseSensitive: false)
        XCTAssertEqual(ranges.map(\.location), [0, 2])
    }
}

final class ThemeColorsTests: XCTestCase {
    func testBuiltinsAreDark() {
        for theme in RenderTheme.allCases {
            XCTAssertTrue(ThemeColors.builtin(theme).isDark)
        }
        XCTAssertFalse(ThemeColors.light.isDark)
    }

    func testCodableRoundTrip() throws {
        let original = ThemeColors.builtin(.solarized)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ThemeColors.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testJSObjectAndInlineStyleContainColors() {
        let c = ThemeColors.builtin(.default)
        let js = c.jsObjectLiteral()
        XCTAssertTrue(js.contains("\"background\""))
        XCTAssertTrue(js.contains(c.link))
        XCTAssertTrue(js.contains("\"mermaid\":\"dark\""))
        let style = c.inlineBodyStyle()
        XCTAssertTrue(style.contains("--pm-link:\(c.link)"))
        XCTAssertTrue(style.contains("background:\(c.background)"))
    }
}

final class ThemeStoreTests: XCTestCase {
    @MainActor
    func testBuiltinResolution() {
        let store = ThemeStore()
        XCTAssertEqual(store.colors(forID: "nord"), .builtin(.nord))
        XCTAssertEqual(store.colors(forID: "bogus"), .builtin(.default))
        XCTAssertEqual(store.name(forID: "one-dark"), "One Dark")
    }

    @MainActor
    func testCustomAddResolveDelete() {
        let store = ThemeStore()
        let before = store.customThemes.count
        let id = store.addCustom(name: "Sunset", colors: .light)
        XCTAssertTrue(id.hasPrefix("custom:"))
        XCTAssertEqual(store.colors(forID: id), .light)
        XCTAssertEqual(store.name(forID: id), "Sunset")
        let uuid = store.customTheme(forID: id)!.id
        store.deleteCustom(uuid)
        XCTAssertEqual(store.customThemes.count, before)
        XCTAssertEqual(store.colors(forID: id), .builtin(.default)) // falls back after delete
    }
}

final class AppStateTabTests: XCTestCase {
    private func tempMarkdown(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pm-\(UUID()).md")
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @MainActor
    func testOpenReplacesPristineUntitledThenDedupes() throws {
        let state = AppState()
        XCTAssertEqual(state.documents.count, 1)
        XCTAssertNil(state.active.fileURL)

        let url = try tempMarkdown("# A")
        defer { try? FileManager.default.removeItem(at: url) }

        state.open(url)
        XCTAssertEqual(state.documents.count, 1, "pristine untitled tab is replaced, not stacked")
        XCTAssertEqual(state.active.fileURL?.lastPathComponent, url.lastPathComponent)

        state.open(url)
        XCTAssertEqual(state.documents.count, 1, "re-opening the same file focuses its tab")
    }

    @MainActor
    func testNewAndOpenStackTabs() throws {
        let state = AppState()
        let a = try tempMarkdown("# A")
        let b = try tempMarkdown("# B")
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }

        state.open(a)            // replaces pristine → 1
        state.newDocument()      // → 2 (untitled active)
        state.open(b)            // not pristine-single → append → 3
        XCTAssertEqual(state.documents.count, 3)
        XCTAssertEqual(state.active.fileURL?.lastPathComponent, b.lastPathComponent)
    }

    @MainActor
    func testCloseActivatesNeighborAndNeverEmpties() throws {
        let state = AppState()
        state.newDocument()
        state.newDocument()
        XCTAssertEqual(state.documents.count, 3)

        let active = state.active
        state.closeDocument(active)       // non-dirty → no prompt
        XCTAssertEqual(state.documents.count, 2)
        XCTAssertNotEqual(state.activeID, active.id)

        state.closeActiveDocument()
        state.closeActiveDocument()       // closing the last replaces with a fresh untitled
        XCTAssertEqual(state.documents.count, 1)
        XCTAssertNil(state.active.fileURL)
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
