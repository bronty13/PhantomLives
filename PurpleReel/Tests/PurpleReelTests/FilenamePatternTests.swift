import XCTest
@testable import PurpleReel

/// Coverage for the C4 file-name pattern picker that drives the
/// Convert dialog's live Example preview and the actual output URL
/// construction inside `TranscodeService.outputURL(...)`.
final class FilenamePatternTests: XCTestCase {

    // MARK: - Test fixtures

    private let h264Preset = TranscodePreset(
        id: "test-h264", name: "H.264 1080p",
        avPresetName: "AVAssetExportPreset1920x1080",
        fileExtension: "mp4", suffix: "_h264_1080p",
        category: .web, alwaysAvailable: false, ffmpegArgs: nil
    )

    private let dnxhrPreset = TranscodePreset(
        id: "test-dnxhr-hq", name: "DNxHR HQ (1080p)",
        avPresetName: "",
        fileExtension: "mov", suffix: "_dnxhr_hq",
        category: .dnxhr, alwaysAvailable: true,
        ffmpegArgs: ["-y", "-i", "{IN}", "-c:v", "dnxhd",
                      "-profile:v", "dnxhr_hq", "{OUT}"]
    )

    // MARK: - Stem construction

    func testOriginalOnlyStemDropsAllSuffixes() {
        let stem = TranscodeService.stem(
            from: "2020-02-16 Rach (1)",
            preset: h264Preset,
            pattern: .originalOnly
        )
        XCTAssertEqual(stem, "2020-02-16 Rach (1)")
    }

    func testOriginalPlusPresetNameStripsWhitespaceAndParens() {
        let stem = TranscodeService.stem(
            from: "2020-02-16 Rach (1)",
            preset: h264Preset,
            pattern: .originalPlusPresetName
        )
        // "H.264 1080p" → slug "H2641080p" (strip space + dot + parens)
        XCTAssertEqual(stem, "2020-02-16 Rach (1)-H2641080p")
    }

    func testOriginalPlusPresetNameOnDNxHRDropsParens() {
        let stem = TranscodeService.stem(
            from: "clip",
            preset: dnxhrPreset,
            pattern: .originalPlusPresetName
        )
        // "DNxHR HQ (1080p)" → "DNxHRHQ1080p"
        XCTAssertEqual(stem, "clip-DNxHRHQ1080p")
    }

    func testOriginalPlusSuffixUsesPresetSuffixVerbatim() {
        let stem = TranscodeService.stem(
            from: "clip",
            preset: h264Preset,
            pattern: .originalPlusSuffix
        )
        XCTAssertEqual(stem, "clip_h264_1080p")
    }

    // MARK: - Pattern enum

    func testAllPatternsHaveDistinctDisplayNames() {
        let names = FilenamePattern.allCases.map(\.displayName)
        XCTAssertEqual(names.count, Set(names).count,
                        "Filename patterns should have distinct display names")
    }

    func testDefaultPatternIsOriginalPlusSuffix() {
        // PurpleReel's legacy default — sticky for users upgrading
        // from the pre-C4 ConvertSheet to avoid surprise renames.
        let state = ConvertSheetState(
            assets: [],
            preset: h264Preset,
            destinationDir: "/tmp",
            keepFolderStructure: false,
            skipExisting: true
        )
        XCTAssertEqual(state.filenamePattern, .originalPlusSuffix)
    }

    // MARK: - Codable round-trip (for sticky UserDefaults persistence)

    func testPatternRoundTripsViaRawValue() {
        for pattern in FilenamePattern.allCases {
            let raw = pattern.rawValue
            let back = FilenamePattern(rawValue: raw)
            XCTAssertEqual(back, pattern,
                            "Pattern rawValue round-trip failed for \(pattern)")
        }
    }

    // MARK: - outputURL collision counter

    /// `outputURL` walks the same numeric-suffix collision path the
    /// existing API uses; the pattern overload just changes the stem
    /// shape. Verify that two consecutive calls in the same empty
    /// directory don't collide with each other.
    func testOutputURLWithPatternIsCollisionFreeInEmptyDirectory() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("purplereel-fp-\(UUID().uuidString)",
                                     isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let src = URL(fileURLWithPath: "/tmp/source.mov")
        let url = TranscodeService.outputURL(
            for: src, preset: h264Preset,
            in: tempRoot, pattern: .originalPlusPresetName
        )
        XCTAssertEqual(
            url.lastPathComponent,
            "source-H2641080p.mp4",
            "Expected stem with no collision suffix"
        )
    }

    /// When the candidate path exists, the helper falls back to a
    /// `_N` numeric suffix.
    func testOutputURLAppendsCounterOnCollision() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("purplereel-fp-coll-\(UUID().uuidString)",
                                     isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        // Pre-create the file that would collide.
        let collidingURL = tempRoot.appendingPathComponent("source-H2641080p.mp4")
        FileManager.default.createFile(atPath: collidingURL.path, contents: Data())

        let src = URL(fileURLWithPath: "/tmp/source.mov")
        let url = TranscodeService.outputURL(
            for: src, preset: h264Preset,
            in: tempRoot, pattern: .originalPlusPresetName
        )
        XCTAssertEqual(url.lastPathComponent, "source-H2641080p_1.mp4",
                        "Expected `_1` counter to avoid collision")
    }
}
