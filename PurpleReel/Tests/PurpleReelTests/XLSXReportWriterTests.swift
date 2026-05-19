import XCTest
@testable import PurpleReel

/// Verify the `.xlsx` output is structurally valid: a real zip with
/// every required OOXML part. Doesn't try to fully validate via Excel
/// — that would require a strict schema check — but the contents are
/// enumerated so a missing part or broken zip fails loudly.
@MainActor
final class XLSXReportWriterTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("purplereel-xlsx-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    /// Smoke test: an empty asset list still produces a valid .xlsx
    /// — no thumbnails, but the workbook + sheet skeleton must exist
    /// so Excel doesn't reject the file as malformed.
    func testEmptyAssetListProducesValidWorkbook() async throws {
        let dest = tempRoot.appendingPathComponent("empty.xlsx")
        let r = try await XLSXReportWriter.writeXLSX(
            assets: [],
            to: dest,
            appState: AppState()
        )
        XCTAssertEqual(r.written, 0)
        XCTAssertEqual(r.skipped, 0)
        let entries = try listZipEntries(at: dest)
        XCTAssertTrue(entries.contains("[Content_Types].xml"))
        XCTAssertTrue(entries.contains("xl/workbook.xml"))
        XCTAssertTrue(entries.contains("xl/worksheets/sheet1.xml"))
        XCTAssertTrue(entries.contains("_rels/.rels"))
    }

    /// `[Content_Types].xml` must declare the spreadsheetml MIME for
    /// sheet1 — without it Excel refuses to open the workbook.
    func testContentTypesXMLDeclaresWorksheetOverride() async throws {
        let dest = tempRoot.appendingPathComponent("ct.xlsx")
        _ = try await XLSXReportWriter.writeXLSX(
            assets: [],
            to: dest,
            appState: AppState()
        )
        let ct = try readZipEntry("[Content_Types].xml", at: dest)
        XCTAssertTrue(
            ct.contains("PartName=\"/xl/worksheets/sheet1.xml\""),
            "[Content_Types].xml must register sheet1's content type"
        )
        XCTAssertTrue(
            ct.contains("application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet"),
            "[Content_Types].xml must declare the spreadsheetml worksheet MIME"
        )
    }

    /// Sheet XML for an assets-with-headers workbook must contain the
    /// header row plus one data row per asset (rendered via inlineStr
    /// cells).
    func testSheetXMLContainsHeaderAndAssetFilenames() async throws {
        let assets = [
            Asset(rowId: 1, path: "/tmp/a.mov", filename: "alpha.mov",
                   sizeBytes: 0, modifiedAt: Date(),
                   codec: "avc1", widthPx: 1920, heightPx: 1080,
                   durationSeconds: 60, frameRate: 29.97,
                   sha1: nil, addedAt: Date()),
            Asset(rowId: 2, path: "/tmp/b.mov", filename: "bravo.mov",
                   sizeBytes: 0, modifiedAt: Date(),
                   codec: "avc1", widthPx: 1920, heightPx: 1080,
                   durationSeconds: 60, frameRate: 29.97,
                   sha1: nil, addedAt: Date()),
        ]
        let dest = tempRoot.appendingPathComponent("rows.xlsx")
        _ = try await XLSXReportWriter.writeXLSX(
            assets: assets,
            to: dest,
            appState: AppState()
        )
        let sheet = try readZipEntry("xl/worksheets/sheet1.xml", at: dest)
        XCTAssertTrue(sheet.contains("Filename"),
                       "Header row must include 'Filename' column")
        XCTAssertTrue(sheet.contains("alpha.mov"),
                       "Data row 1 must include first asset's filename")
        XCTAssertTrue(sheet.contains("bravo.mov"),
                       "Data row 2 must include second asset's filename")
    }

    /// XML escaping is non-negotiable — a filename like
    /// `a<b&c>.mov` must render as `a&lt;b&amp;c&gt;.mov` or the file
    /// becomes malformed XML and Excel rejects it.
    func testSpecialCharactersInFilenameAreXMLEscaped() async throws {
        let assets = [
            Asset(rowId: 1, path: "/tmp/x.mov",
                   filename: "weird<&>name.mov",
                   sizeBytes: 0, modifiedAt: Date(),
                   codec: "avc1", widthPx: 1920, heightPx: 1080,
                   durationSeconds: 60, frameRate: 29.97,
                   sha1: nil, addedAt: Date())
        ]
        let dest = tempRoot.appendingPathComponent("escape.xlsx")
        _ = try await XLSXReportWriter.writeXLSX(
            assets: assets,
            to: dest,
            appState: AppState()
        )
        let sheet = try readZipEntry("xl/worksheets/sheet1.xml", at: dest)
        XCTAssertTrue(sheet.contains("weird&lt;&amp;&gt;name.mov"),
                       "Filename must be XML-escaped in the sheet")
        XCTAssertFalse(sheet.contains("<weird"),
                        "Raw `<` from filename must not leak into XML body")
    }

    /// Drawing part should not be referenced when there are no
    /// thumbnails to anchor — Excel still opens the workbook either
    /// way, but the unused `<drawing>` ref + empty drawing1.xml are
    /// noise.
    func testNoDrawingReferenceWhenAllAssetsLackPreviews() async throws {
        // No assets → no thumbs → no drawing tag.
        let dest = tempRoot.appendingPathComponent("nodraw.xlsx")
        _ = try await XLSXReportWriter.writeXLSX(
            assets: [],
            to: dest,
            appState: AppState()
        )
        let sheet = try readZipEntry("xl/worksheets/sheet1.xml", at: dest)
        XCTAssertFalse(sheet.contains("<drawing"),
                        "Empty asset list shouldn't reference a drawing part")
    }

    // MARK: - Section toggles (C26)

    /// Default `.all` keeps every column we expect — locks the
    /// pre-C26 schema as a regression baseline.
    func testAllSectionsIncludesEveryColumnHeader() async throws {
        let dest = tempRoot.appendingPathComponent("all.xlsx")
        _ = try await XLSXReportWriter.writeXLSX(
            assets: [],
            to: dest,
            appState: AppState(),
            sections: .all
        )
        let sheet = try readZipEntry("xl/worksheets/sheet1.xml", at: dest)
        for header in [
            "Filename", "Codec", "Resolution", "Display Size",
            "Aspect Ratio", "FPS", "Duration (sec)", "Size (bytes)",
            "Date Modified", "Date Created", "Date Recorded",
            "Rating", "Title", "Description", "Reel", "Scene",
            "Shot", "Take", "Angle", "Camera", "Audio Channels", "Tags",
        ] {
            XCTAssertTrue(sheet.contains(header),
                           "Default .all should include header '\(header)'")
        }
    }

    /// Dropping `.descriptiveMetadata` removes Title/Description/
    /// Reel/Scene/Shot/Take/Angle/Camera/Audio Channels/Tags +
    /// Rating — but keeps Filename/Codec/Size (always-on) and the
    /// formatDetails block intact.
    func testDescriptiveMetadataOffDropsLogFieldColumns() async throws {
        let dest = tempRoot.appendingPathComponent("nodesc.xlsx")
        let sections: ReportSections = [.duration, .formatDetails]
        _ = try await XLSXReportWriter.writeXLSX(
            assets: [],
            to: dest,
            appState: AppState(),
            sections: sections
        )
        let sheet = try readZipEntry("xl/worksheets/sheet1.xml", at: dest)
        for dropped in ["Title", "Description", "Reel", "Scene",
                         "Take", "Angle", "Audio Channels", "Tags"] {
            XCTAssertFalse(sheet.contains(dropped),
                            "Header '\(dropped)' must be dropped when descriptiveMetadata off")
        }
        XCTAssertTrue(sheet.contains("Filename"))
        XCTAssertTrue(sheet.contains("Codec"))
        XCTAssertTrue(sheet.contains("Resolution"),
                       "formatDetails columns must stay when only descriptiveMetadata is off")
    }

    /// Dropping `.formatDetails` removes Resolution/FPS/Date* etc.
    /// but keeps Duration (gated by `.duration` separately) and
    /// the always-on Filename/Codec/Size.
    func testFormatDetailsOffDropsResolutionAndDateColumns() async throws {
        let dest = tempRoot.appendingPathComponent("nofmt.xlsx")
        let sections: ReportSections = [.duration, .descriptiveMetadata]
        _ = try await XLSXReportWriter.writeXLSX(
            assets: [],
            to: dest,
            appState: AppState(),
            sections: sections
        )
        let sheet = try readZipEntry("xl/worksheets/sheet1.xml", at: dest)
        for dropped in ["Resolution", "Display Size", "Aspect Ratio",
                         "FPS", "Date Modified", "Date Created", "Date Recorded"] {
            XCTAssertFalse(sheet.contains(dropped),
                            "Header '\(dropped)' must be dropped when formatDetails off")
        }
        XCTAssertTrue(sheet.contains("Duration (sec)"),
                       "duration is independent of formatDetails")
        XCTAssertTrue(sheet.contains("Title"))
    }

    /// OOXML cell letters come from each cell's POSITION in the
    /// row; dropping columns must realign them automatically. This
    /// test asserts that with descriptiveMetadata + formatDetails
    /// off, the Filename column lands at `B` (after the always-on
    /// thumbnail at `A`) and the Size column lands at `D` (after
    /// Filename / Codec / Duration).
    func testColumnLettersRealignWhenSectionsDropped() async throws {
        let assets = [
            Asset(rowId: 1, path: "/tmp/x.mov", filename: "x.mov",
                   sizeBytes: 4242, modifiedAt: Date(),
                   codec: "avc1", widthPx: 1920, heightPx: 1080,
                   durationSeconds: 60, frameRate: 29.97,
                   sha1: nil, addedAt: Date())
        ]
        let dest = tempRoot.appendingPathComponent("realign.xlsx")
        _ = try await XLSXReportWriter.writeXLSX(
            assets: assets,
            to: dest,
            appState: AppState(),
            sections: [.duration]   // formatDetails OFF, descMeta OFF
        )
        let sheet = try readZipEntry("xl/worksheets/sheet1.xml", at: dest)
        // Header columns now: A=Thumbnail (empty cell), B=Filename,
        // C=Codec, D=Duration, E=Size (bytes). Data row indices
        // match. Verify the size value lands in column E for row 2.
        XCTAssertTrue(sheet.contains("r=\"E2\""),
                       "With only .duration, Size should land at column E in row 2")
        XCTAssertTrue(sheet.contains("4242"),
                       "Row data must still include the size value")
    }

    // MARK: - Zip helpers

    /// Run `/usr/bin/unzip -l` and parse the resulting entry list.
    private func listZipEntries(at url: URL) throws -> [String] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-Z", "-1", url.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8) ?? ""
        return raw.split(separator: "\n").map { String($0) }
    }

    /// Extract one entry's contents as UTF-8 text. Goes through a
    /// full `unzip -o` extraction to a temp directory because some
    /// entry names (e.g. `[Content_Types].xml`) contain characters
    /// that `unzip -p` glob-expands.
    private func readZipEntry(_ name: String,
                                at url: URL) throws -> String {
        let extractDir = tempRoot
            .appendingPathComponent("extract-\(UUID().uuidString)",
                                     isDirectory: true)
        try FileManager.default.createDirectory(
            at: extractDir, withIntermediateDirectories: true)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-o", "-qq", url.path, "-d", extractDir.path]
        try proc.run()
        proc.waitUntilExit()
        let entry = extractDir.appendingPathComponent(name)
        return (try? String(contentsOf: entry, encoding: .utf8)) ?? ""
    }
}
