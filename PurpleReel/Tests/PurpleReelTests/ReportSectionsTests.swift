import XCTest
@testable import PurpleReel

/// Coverage for C12's `ReportSections` OptionSet and the section-
/// gating in `ReportExporter.writeCSV(...)`. HTML follows the same
/// gating logic; the XLSX writer ships the full schema regardless
/// (the OOXML column-letter alignment makes per-section column
/// dropping a separate follow-up).
@MainActor
final class ReportSectionsTests: XCTestCase {

    // MARK: - OptionSet basics

    func testLockedContainsFileSizeAndFileType() {
        XCTAssertTrue(ReportSections.locked.contains(.fileSize))
        XCTAssertTrue(ReportSections.locked.contains(.fileType))
        XCTAssertFalse(ReportSections.locked.contains(.duration))
    }

    func testAllContainsEveryDefinedSection() {
        XCTAssertTrue(ReportSections.all.contains(.fileSize))
        XCTAssertTrue(ReportSections.all.contains(.fileType))
        XCTAssertTrue(ReportSections.all.contains(.duration))
        XCTAssertTrue(ReportSections.all.contains(.formatDetails))
        XCTAssertTrue(ReportSections.all.contains(.descriptiveMetadata))
    }

    // MARK: - CSV column gating

    private func makeAsset() -> Asset {
        Asset(
            rowId: 1, path: "/tmp/clip.mov",
            filename: "clip.mov",
            sizeBytes: 1_234_567,
            modifiedAt: Date(),
            codec: "avc1",
            widthPx: 1920, heightPx: 1080,
            durationSeconds: 60,
            frameRate: 29.97,
            sha1: nil,
            addedAt: Date()
        )
    }

    func testCSVWithAllSectionsEmitsFullColumnList() throws {
        let asset = makeAsset()
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("report-all-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try ReportExporter.writeCSV(
            assets: [asset], to: tempURL,
            appState: AppState(),
            sections: .all
        )
        let body = try String(contentsOf: tempURL, encoding: .utf8)
        XCTAssertTrue(body.contains("Filename"))
        XCTAssertTrue(body.contains("Duration (sec)"))
        XCTAssertTrue(body.contains("Resolution"))
        XCTAssertTrue(body.contains("Title"))
        XCTAssertTrue(body.contains("Tags"))
    }

    func testCSVWithOnlyLockedSectionsEmitsBareMinimum() throws {
        let asset = makeAsset()
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("report-min-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try ReportExporter.writeCSV(
            assets: [asset], to: tempURL,
            appState: AppState(),
            sections: .locked
        )
        let body = try String(contentsOf: tempURL, encoding: .utf8)
        XCTAssertTrue(body.contains("Filename"),
                       "Filename column must always emit (File type group)")
        XCTAssertTrue(body.contains("Size (bytes)"),
                       "Size column must always emit (File size group)")
        // Verify the gated columns disappear when their section is off.
        XCTAssertFalse(body.contains("Duration (sec)"),
                        "Duration must drop when .duration section is off")
        XCTAssertFalse(body.contains("Resolution"),
                        "Resolution must drop when .formatDetails section is off")
        XCTAssertFalse(body.contains("Title"),
                        "Title must drop when .descriptiveMetadata section is off")
    }

    /// Duration on + formatDetails off + descriptiveMetadata off:
    /// the duration column should appear in the right position
    /// (between Codec and Size), and nothing else from the gated
    /// groups should land.
    func testCSVWithOnlyDurationSectionGated() throws {
        let asset = makeAsset()
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("report-dur-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        var sections = ReportSections.locked
        sections.insert(.duration)
        try ReportExporter.writeCSV(
            assets: [asset], to: tempURL,
            appState: AppState(),
            sections: sections
        )
        let body = try String(contentsOf: tempURL, encoding: .utf8)
        XCTAssertTrue(body.contains("Duration (sec)"))
        XCTAssertFalse(body.contains("Resolution"))
        XCTAssertFalse(body.contains("Tags"))
    }
}
