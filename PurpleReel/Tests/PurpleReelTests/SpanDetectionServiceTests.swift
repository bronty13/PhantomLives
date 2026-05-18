import XCTest
@testable import PurpleReel

final class SpanDetectionServiceTests: XCTestCase {

    // MARK: - Fixture helper

    private func makeAsset(filename: String,
                            dir: String = "/Volumes/CardA/DCIM/100EOS",
                            mod: Date,
                            codec: String? = "hvc1",
                            width: Int? = 1920,
                            height: Int? = 1080,
                            fps: Double? = 29.97,
                            audio: String? = "aac ") -> Asset {
        Asset(
            rowId: nil,
            path: "\(dir)/\(filename)",
            filename: filename,
            sizeBytes: 4_000_000_000,
            modifiedAt: mod,
            codec: codec,
            widthPx: width,
            heightPx: height,
            durationSeconds: 600,
            frameRate: fps,
            sha1: nil,
            addedAt: Date(),
            audioCodec: audio,
            recordedAt: nil,
            createdAt: nil,
            isVFR: false
        )
    }

    // MARK: - Happy paths

    func testCanonAndSimilarSequentialNamesGroupAsOneSpan() {
        let t = Date()
        let assets = [
            makeAsset(filename: "MVI_0001.MOV", mod: t),
            makeAsset(filename: "MVI_0002.MOV", mod: t.addingTimeInterval(60)),
            makeAsset(filename: "MVI_0003.MOV", mod: t.addingTimeInterval(120)),
        ]
        let groups = SpanDetectionService.detect(in: assets)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].segments.count, 3)
        XCTAssertEqual(groups[0].segments.map(\.filename),
                       ["MVI_0001.MOV", "MVI_0002.MOV", "MVI_0003.MOV"])
        // Label carries the common prefix + extension.
        XCTAssertTrue(groups[0].label.contains("MVI_"))
        XCTAssertTrue(groups[0].label.contains("MOV"))
        XCTAssertTrue(groups[0].label.contains("3 segments"))
    }

    func testSonyXAVCStyleNamingDetected() {
        let t = Date()
        let assets = [
            makeAsset(filename: "C0001.MP4", mod: t),
            makeAsset(filename: "C0002.MP4", mod: t.addingTimeInterval(60)),
        ]
        let groups = SpanDetectionService.detect(in: assets)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].segments.count, 2)
    }

    func testC300PureDigitNamingDetected() {
        let t = Date()
        let assets = [
            makeAsset(filename: "00000.MXF", mod: t),
            makeAsset(filename: "00001.MXF", mod: t.addingTimeInterval(60)),
            makeAsset(filename: "00002.MXF", mod: t.addingTimeInterval(120)),
        ]
        let groups = SpanDetectionService.detect(in: assets)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].segments.count, 3)
    }

    func testTotalDurationSumsAcrossSegments() {
        let t = Date()
        var a1 = makeAsset(filename: "MVI_0001.MOV", mod: t)
        a1.durationSeconds = 300
        var a2 = makeAsset(filename: "MVI_0002.MOV", mod: t.addingTimeInterval(60))
        a2.durationSeconds = 250
        let groups = SpanDetectionService.detect(in: [a1, a2])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].totalDuration, 550, accuracy: 0.01)
    }

    // MARK: - Negative cases — must not falsely glue

    func testNonSequentialDigitsAreNotGrouped() {
        let t = Date()
        let assets = [
            makeAsset(filename: "MVI_0001.MOV", mod: t),
            makeAsset(filename: "MVI_0003.MOV", mod: t.addingTimeInterval(60)),
        ]
        XCTAssertEqual(SpanDetectionService.detect(in: assets).count, 0)
    }

    func testModtimeGapBeyond120sBreaksSpan() {
        let t = Date()
        let assets = [
            makeAsset(filename: "MVI_0001.MOV", mod: t),
            // 3 minutes later — not the same take.
            makeAsset(filename: "MVI_0002.MOV", mod: t.addingTimeInterval(180)),
        ]
        XCTAssertEqual(SpanDetectionService.detect(in: assets).count, 0)
    }

    func testCodecMismatchBreaksSpan() {
        let t = Date()
        let assets = [
            makeAsset(filename: "MVI_0001.MOV", mod: t, codec: "hvc1"),
            makeAsset(filename: "MVI_0002.MOV", mod: t.addingTimeInterval(60), codec: "avc1"),
        ]
        XCTAssertEqual(SpanDetectionService.detect(in: assets).count, 0)
    }

    func testResolutionMismatchBreaksSpan() {
        let t = Date()
        let assets = [
            makeAsset(filename: "MVI_0001.MOV", mod: t),
            makeAsset(filename: "MVI_0002.MOV", mod: t.addingTimeInterval(60),
                       width: 3840, height: 2160),
        ]
        XCTAssertEqual(SpanDetectionService.detect(in: assets).count, 0)
    }

    func testFrameRateMismatchBreaksSpan() {
        let t = Date()
        let assets = [
            makeAsset(filename: "MVI_0001.MOV", mod: t, fps: 29.97),
            makeAsset(filename: "MVI_0002.MOV", mod: t.addingTimeInterval(60), fps: 23.976),
        ]
        XCTAssertEqual(SpanDetectionService.detect(in: assets).count, 0)
    }

    func testDifferentFoldersAreNeverGrouped() {
        let t = Date()
        let assets = [
            makeAsset(filename: "MVI_0001.MOV",
                       dir: "/Volumes/CardA/DCIM/100EOS", mod: t),
            makeAsset(filename: "MVI_0002.MOV",
                       dir: "/Volumes/CardA/DCIM/101EOS",
                       mod: t.addingTimeInterval(60)),
        ]
        XCTAssertEqual(SpanDetectionService.detect(in: assets).count, 0)
    }

    func testMixedExtensionsInSameFolderAreNotGrouped() {
        let t = Date()
        // Same prefix + sequential digits but `.MOV` vs `.MP4` —
        // never the same recording session.
        let assets = [
            makeAsset(filename: "MVI_0001.MOV", mod: t),
            makeAsset(filename: "MVI_0002.MP4", mod: t.addingTimeInterval(60)),
        ]
        XCTAssertEqual(SpanDetectionService.detect(in: assets).count, 0)
    }

    func testSingletonFilesAreNeverReportedAsSpans() {
        let t = Date()
        let assets = [makeAsset(filename: "MVI_0001.MOV", mod: t)]
        XCTAssertEqual(SpanDetectionService.detect(in: assets).count, 0)
    }

    func testEmptyInputReturnsEmptyOutput() {
        XCTAssertEqual(SpanDetectionService.detect(in: []).count, 0)
    }

    func testNonDigitFilenameIsIgnored() {
        let t = Date()
        let assets = [
            makeAsset(filename: "clip.MOV", mod: t),
            makeAsset(filename: "intro.MOV", mod: t.addingTimeInterval(60)),
        ]
        XCTAssertEqual(SpanDetectionService.detect(in: assets).count, 0)
    }

    // MARK: - Multi-group cases

    func testTwoSeparateSpansInSameFolderEmittedSeparately() {
        let t = Date()
        let assets = [
            // First span: MVI_0001..0002
            makeAsset(filename: "MVI_0001.MOV", mod: t),
            makeAsset(filename: "MVI_0002.MOV", mod: t.addingTimeInterval(60)),
            // Gap in numbering — span breaks.
            // Second span: MVI_0010..0011 (modtime well separated to be safe).
            makeAsset(filename: "MVI_0010.MOV", mod: t.addingTimeInterval(86400)),
            makeAsset(filename: "MVI_0011.MOV", mod: t.addingTimeInterval(86400 + 60)),
        ]
        let groups = SpanDetectionService.detect(in: assets)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].segments.count, 2)
        XCTAssertEqual(groups[1].segments.count, 2)
    }
}
