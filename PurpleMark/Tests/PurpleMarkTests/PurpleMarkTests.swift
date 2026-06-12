import XCTest
import WebKit
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

    func testStandaloneHTMLBundlesSanitizer() {
        let html = RenderCore.standaloneHTML(markdown: "x", colors: .builtin(.default), width: .default)
        XCTAssertTrue(html.contains("DOMPurify"), "DOMPurify must be inlined")
        XCTAssertTrue(html.contains("window.__PM_ALLOW_RAW_HTML__ = false"),
                      "sanitization is on by default")
        let raw = RenderCore.standaloneHTML(markdown: "x", colors: .builtin(.default),
                                            width: .default, allowRawHTML: true)
        XCTAssertTrue(raw.contains("window.__PM_ALLOW_RAW_HTML__ = true"))
    }

    func testAppScriptExtractionStillFindsIIFE() {
        // The chunked-render rewrite must keep the page JS as one IIFE — the
        // export path extracts it textually.
        let html = RenderCore.standaloneHTML(markdown: "x", colors: .builtin(.default), width: .default)
        XCTAssertTrue(html.contains("__PM_PENDING__"), "app script must be extracted into the export")
        XCTAssertTrue(html.contains("sanitizeHTML"), "export shares the sanitizing render path")
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

/// End-to-end sanitization proof: render hostile markdown through the real
/// pipeline in a real WKWebView and verify the script never ran while benign
/// inline HTML survived.
@MainActor
final class SanitizationIntegrationTests: XCTestCase {
    func testScriptsStrippedBenignHTMLKept() async throws {
        let md = """
        <script>window.__pwned__ = 1;</script>

        <img src="x" onerror="window.__pwned2__ = 1">

        <details><summary>benign</summary>kept</details>

        plain *text*
        """
        let html = RenderCore.standaloneHTML(markdown: md)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        webView.loadHTMLString(html, baseURL: nil)

        // Wait for the async render to land.
        var rendered = false
        for _ in 0..<100 {
            try await Task.sleep(nanoseconds: 50_000_000)
            if let count = try? await webView.evaluateJavaScript(
                "document.querySelectorAll('#content details').length") as? Int, count > 0 {
                rendered = true
                break
            }
        }
        XCTAssertTrue(rendered, "the page should render the markdown")

        let pwned = try await webView.evaluateJavaScript(
            "(window.__pwned__ === 1) || (window.__pwned2__ === 1)") as? Bool
        XCTAssertEqual(pwned, false, "embedded scripts/handlers must never execute")
        let handlerGone = try await webView.evaluateJavaScript(
            "document.querySelector('#content img[onerror]') == null") as? Bool
        XCTAssertEqual(handlerGone, true, "event handler attributes are stripped")
        let detailsKept = try await webView.evaluateJavaScript(
            "document.querySelector('#content details') != null") as? Bool
        XCTAssertEqual(detailsKept, true, "benign inline HTML still renders")
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
        s.themeRaw = "solarized"
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

final class FileLoaderTests: XCTestCase {
    func testDecodesPlainUTF8() {
        let loaded = FileLoader.decode(Data("# héllo ✨".utf8))
        XCTAssertEqual(loaded.text, "# héllo ✨")
        XCTAssertEqual(loaded.encoding, .utf8)
        XCTAssertEqual(loaded.byteSize, Data("# héllo ✨".utf8).count)
    }

    func testStripsUTF8BOM() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("hello".utf8))
        let loaded = FileLoader.decode(data)
        XCTAssertEqual(loaded.text, "hello", "BOM must not land in the editor")
    }

    func testDecodesUTF16WithBOM() {
        let data = "héllo".data(using: .utf16)!   // includes a BOM
        let loaded = FileLoader.decode(data)
        XCTAssertEqual(loaded.text, "héllo")
    }

    func testFallsBackForLatin1Bytes() {
        // 0xE9 is 'é' in Latin-1 and invalid as standalone UTF-8.
        let data = Data([0x63, 0x61, 0x66, 0xE9]) // "café"
        let loaded = FileLoader.decode(data)
        XCTAssertEqual(loaded.text, "café")
    }

    func testEmptyData() {
        let loaded = FileLoader.decode(Data())
        XCTAssertEqual(loaded.text, "")
        XCTAssertEqual(loaded.byteSize, 0)
    }
}

final class DocumentIndexTests: XCTestCase {
    func testLineStartOffsets() {
        let idx = DocumentIndex.build(from: "ab\ncd\n\nx")
        XCTAssertEqual(idx.lineStartOffsets, [0, 3, 6, 7])
        XCTAssertEqual(idx.stats.lines, 4)
        XCTAssertEqual(idx.lineIndex(forUTF16Offset: 0), 0)
        XCTAssertEqual(idx.lineIndex(forUTF16Offset: 2), 0)
        XCTAssertEqual(idx.lineIndex(forUTF16Offset: 3), 1)
        XCTAssertEqual(idx.lineIndex(forUTF16Offset: 7), 3)
    }

    func testFenceRangesAndMembership() {
        let md = """
        # Title
        ```
        code
        # not a heading
        ```
        after
        ~~~
        more
        """
        let idx = DocumentIndex.build(from: md)
        XCTAssertEqual(idx.fenceLineRanges.first, 1..<5)
        XCTAssertEqual(idx.fenceLineRanges.last, 6..<8, "unclosed fence runs to the end")
        XCTAssertTrue(idx.isLineInFence(2))
        XCTAssertFalse(idx.isLineInFence(0))
        XCTAssertFalse(idx.isLineInFence(5))
        XCTAssertEqual(idx.outline.map(\.title), ["Title"])
    }

    func testFenceCharacterRanges() {
        let md = "a\n```\nb\n```\nc"
        let idx = DocumentIndex.build(from: md)
        let ranges = idx.fenceCharacterRanges(totalLength: (md as NSString).length)
        XCTAssertEqual(ranges, [NSRange(location: 2, length: 10)]) // "```\nb\n```\n"
    }

    func testMatchesOutlineParserOnMixedDocument() {
        let md = """
        # One
        text **bold**
        ```swift
        # comment
        ```
        ## Two
        - item
        """
        let idx = DocumentIndex.build(from: md)
        XCTAssertEqual(idx.outline, OutlineParser.outline(from: md))
        XCTAssertEqual(idx.stats, OutlineParser.stats(from: md))
        XCTAssertEqual(idx.stats.words, OutlineParser.stats(from: md).words)
    }

    func testEmptyDocument() {
        let idx = DocumentIndex.build(from: "")
        XCTAssertEqual(idx.lineStartOffsets, [0])
        XCTAssertEqual(idx.stats.lines, 0)
        XCTAssertTrue(idx.outline.isEmpty)
        XCTAssertTrue(idx.fenceLineRanges.isEmpty)
    }
}

final class ViewportHighlighterTests: XCTestCase {
    @MainActor
    func testSubRangeHighlightLeavesOutsideUntouched() {
        let md = "# Outside\n\n# Inside\n\nplain"
        let storage = NSTextStorage(string: md)
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        MarkdownHighlighter.applyBase(to: storage, baseFont: font)

        // Highlight only the second heading's paragraph.
        let inside = (md as NSString).range(of: "# Inside")
        MarkdownHighlighter.apply(to: storage, baseFont: font, range: inside)

        let insideColor = storage.attribute(.foregroundColor, at: inside.location,
                                            effectiveRange: nil) as? NSColor
        XCTAssertEqual(insideColor, SourcePalette.heading)
        let outsideColor = storage.attribute(.foregroundColor, at: 0,
                                             effectiveRange: nil) as? NSColor
        XCTAssertEqual(outsideColor, SourcePalette.text,
                       "text outside the range keeps base attributes")
    }

    @MainActor
    func testHeadingAnchorsMatchAtSubRangeStart() {
        // ^ must match at the range start when it's a true line start.
        let md = "intro\n# Head\ntail"
        let storage = NSTextStorage(string: md)
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let head = (md as NSString).range(of: "# Head")
        MarkdownHighlighter.apply(to: storage, baseFont: font, range: head)
        let color = storage.attribute(.foregroundColor, at: head.location,
                                      effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, SourcePalette.heading)
    }

    @MainActor
    func testFenceRangesColorCode() {
        let md = "a\n```\ncode here\n```\nb"
        let storage = NSTextStorage(string: md)
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let idx = DocumentIndex.build(from: md)
        let fences = idx.fenceCharacterRanges(totalLength: (md as NSString).length)
        MarkdownHighlighter.apply(to: storage, baseFont: font, fenceRanges: fences)
        let codeLoc = (md as NSString).range(of: "code here").location
        let color = storage.attribute(.foregroundColor, at: codeLoc,
                                      effectiveRange: nil) as? NSColor
        XCTAssertEqual(color, SourcePalette.code)
    }
}

final class FenceIntersectionTests: XCTestCase {
    func testIntersectingFencesOnly() {
        let md = "```\na\n```\nplain\nplain\n```\nb\n```\ntail"
        let ns = md as NSString
        let idx = DocumentIndex.build(from: md)
        XCTAssertEqual(idx.fenceLineRanges.count, 2)

        let plain = ns.range(of: "plain\nplain")
        let around = idx.fenceCharacterRanges(intersecting: plain, totalLength: ns.length)
        XCTAssertTrue(around.isEmpty, "no fence overlaps the plain lines")

        let secondFence = ns.range(of: "b")
        let hits = idx.fenceCharacterRanges(intersecting: secondFence, totalLength: ns.length)
        XCTAssertEqual(hits.count, 1)
    }
}

final class LargeFilePolicyTests: XCTestCase {
    func testSmallFileKeepsEverything() {
        let p = LargeFilePolicy.features(forByteSize: 1_000_000)
        XCTAssertFalse(p.isLarge)
        XCTAssertTrue(p.spellcheckAllowed)
        XCTAssertTrue(p.typographyAllowed)
        XCTAssertTrue(p.focusModesAllowed)
        XCTAssertFalse(p.previewCapped)
    }

    func testLargeFileDegrades() {
        let p = LargeFilePolicy.features(forByteSize: 20_000_000)
        XCTAssertTrue(p.isLarge)
        XCTAssertFalse(p.spellcheckAllowed)
        XCTAssertFalse(p.focusModesAllowed)
        XCTAssertFalse(p.previewCapped, "20MB renders fully")
    }

    func testHugeFileCapsPreview() {
        XCTAssertTrue(LargeFilePolicy.features(forByteSize: 100_000_000).previewCapped)
    }
}

final class DocumentVersionTests: XCTestCase {
    @MainActor
    func testNoteEditedBumpsVersionAndDirty() {
        let doc = Document(text: "hello", fileURL: nil)
        XCTAssertFalse(doc.isDirty)
        let v = doc.textVersion
        doc.storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "x")
        doc.noteEdited()
        XCTAssertEqual(doc.textVersion, v + 1)
        XCTAssertTrue(doc.isDirty)
    }

    @MainActor
    func testProgrammaticReplaceIsNotDirty() {
        let doc = Document(text: "a", fileURL: nil)
        doc.text = "completely new"
        XCTAssertFalse(doc.isDirty)
        XCTAssertEqual(doc.text, "completely new")
    }

    @MainActor
    func testInitBuildsIndexSynchronously() {
        let doc = Document(text: "# Head\n\nbody words here", fileURL: nil)
        XCTAssertEqual(doc.outline.map(\.title), ["Head"])
        XCTAssertEqual(doc.stats.words, 5)   // "#" counts as a word, as before
    }
}

final class MarkdownChunkerTests: XCTestCase {
    func testChunksRoundTripToOriginal() {
        let blocks = (1...200).map { "## Block \($0)\n\nparagraph text for block \($0)\n" }
        let md = blocks.joined(separator: "\n")
        let result = MarkdownChunker.split(md, targetBytes: 500)
        XCTAssertGreaterThan(result.chunks.count, 1)
        XCTAssertEqual(result.chunks.map { String($0.text) }.joined(), md,
                       "concatenated chunks must reproduce the document exactly")
        XCTAssertFalse(result.truncated)
        XCTAssertEqual(result.totalBytes, md.utf8.count)
    }

    func testNeverSplitsInsideFences() {
        let fenced = "```\n" + (1...100).map { "code line \($0)\n\n" }.joined() + "```\n"
        let md = "intro\n\n" + fenced + "\nafter\n"
        let result = MarkdownChunker.split(md, targetBytes: 64)
        // Every chunk must contain an even number of fence delimiters.
        for chunk in result.chunks {
            let fences = chunk.text.components(separatedBy: "\n")
                .filter { $0.hasPrefix("```") }.count
            XCTAssertEqual(fences % 2, 0, "a chunk must not cut a fence open")
        }
        XCTAssertEqual(result.chunks.map { String($0.text) }.joined(), md)
    }

    func testStableHashes() {
        let md = "# A\n\ntext\n\n# B\n\nmore\n"
        let a = MarkdownChunker.split(md, targetBytes: 8)
        let b = MarkdownChunker.split(md, targetBytes: 8)
        XCTAssertEqual(a.chunks.map(\.hash), b.chunks.map(\.hash))
        XCTAssertEqual(a.chunks.map(\.id), Array(0..<a.chunks.count))
    }

    func testLocalEditChangesOneChunkHash() {
        let blocks = (1...40).map { "## Block \($0)\n\n" + String(repeating: "word ", count: 60) + "\n" }
        let md = blocks.joined(separator: "\n")
        let edited = md.replacingOccurrences(of: "Block 20", with: "Block twenty")
        let a = MarkdownChunker.split(md, targetBytes: 400)
        let b = MarkdownChunker.split(edited, targetBytes: 400)
        XCTAssertEqual(a.chunks.count, b.chunks.count)
        let changed = zip(a.chunks, b.chunks).filter { $0.hash != $1.hash }
        XCTAssertEqual(changed.count, 1, "an in-place edit re-renders exactly one chunk")
    }

    func testHoistsReferenceDefinitions() {
        let md = "See [the spec][spec].\n\n" + String(repeating: "filler text\n\n", count: 100)
            + "[spec]: https://example.com\n"
        let result = MarkdownChunker.split(md, targetBytes: 200)
        XCTAssertTrue(result.refDefsSuffix.contains("[spec]: https://example.com"))
    }

    func testCapTruncates() {
        let md = (1...100).map { "paragraph \($0)\n" }.joined(separator: "\n")
        let result = MarkdownChunker.split(md, targetBytes: 64, maxTotalBytes: 200)
        XCTAssertTrue(result.truncated)
        let rendered = result.chunks.map { String($0.text) }.joined()
        XCTAssertTrue(md.hasPrefix(rendered))
        XCTAssertLessThan(rendered.utf8.count, md.utf8.count)
        XCTAssertEqual(result.totalBytes, md.utf8.count, "totalBytes reports the full size")
    }

    func testFNV1aKnownVector() {
        // FNV-1a 64-bit of "a" is 0xaf63dc4c8601ec8c.
        XCTAssertEqual(MarkdownChunker.fnv1a(Substring("a")), 0xaf63dc4c8601ec8c)
    }
}

final class FindCapTests: XCTestCase {
    @MainActor
    func testMatchesAreCapped() {
        let text = String(repeating: "a ", count: FindController.maxMatches + 5_000)
        let find = FindController()
        find.query = "a"
        find.recompute(in: text, version: 1)
        XCTAssertEqual(find.matchCount, FindController.maxMatches)
        XCTAssertTrue(find.matchesCapped)
        XCTAssertEqual(find.matchesVersion, 1)
    }
}

final class DropToOpenTests: XCTestCase {
    @MainActor
    func testOpensMarkdownFilesAndIgnoresOthers() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("pm-drop-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let md = dir.appendingPathComponent("note.md")
        try "# Hello".write(to: md, atomically: true, encoding: .utf8)
        let png = dir.appendingPathComponent("image.png")
        try Data([0x89, 0x50]).write(to: png)

        let state = AppState()
        // Drop a markdown file + an unsupported file + the containing directory.
        let accepted = state.openDroppedFiles([md, png, dir])

        XCTAssertTrue(accepted)                                   // at least one openable → drop accepted
        XCTAssertEqual(state.documents.count, 1)                  // only the .md opened (replaced pristine tab)
        XCTAssertEqual(state.active.fileURL?.lastPathComponent, "note.md")
    }

    @MainActor
    func testRejectsDropWithNoOpenableFiles() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("pm-drop-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let png = dir.appendingPathComponent("image.png")
        try Data([0x89, 0x50]).write(to: png)

        let state = AppState()
        let accepted = state.openDroppedFiles([png])

        XCTAssertFalse(accepted)                                  // nothing openable → drop rejected
        XCTAssertNil(state.active.fileURL)                        // still the pristine untitled tab
    }
}
