import XCTest
@testable import PurpleAtticCore

final class OsxphotosLineTests: XCTestCase {

    func testBenignMakerNotesIsEmbedSkip() {
        let line = "❌️  Error exporting photo (0499EBF7-6445-43DF-BBE5-77489CC0EC48: FL000013.jpg) as /Volumes/PRO-G40/Photos Archive/originals/2002/2002-09/FL000013.jpg: Error:  Bad format (48) for MakerNotes entry 5 - /var/folders/qg/abc/x_exiftool.jpeg"
        XCTAssertEqual(OsxphotosLine.classify(line),
                       .metadataEmbedSkip(uuid: "0499EBF7-6445-43DF-BBE5-77489CC0EC48", file: "FL000013.jpg"))
    }

    func testNotValidHeicIsEmbedSkip() {
        let line = "❌️  Error exporting photo (BD486C37-7D5D-471D-9E00-E0158C7ED63F: IMG_3978.HEIC) as /x/IMG_3978_edited.heic: Error: Not a valid HEIC (looks more like a JPEG) - /var/folders/x"
        if case .metadataEmbedSkip(_, let file) = OsxphotosLine.classify(line) {
            XCTAssertEqual(file, "IMG_3978.HEIC")
        } else { XCTFail("expected metadataEmbedSkip") }
    }

    func testNotValidJpegLooksLikePngIsEmbedSkip() {
        let line = "❌️  Error exporting photo (11520C54-27FD-487F-A08C-5D25CBFE3163: 193.jpeg) as /x/193.jpeg: Error: Not a valid JPEG (looks more like a PNG) - /var/folders/x"
        if case .metadataEmbedSkip = OsxphotosLine.classify(line) {} else { XCTFail("expected embed skip") }
    }

    func testCompanionNoiseSuppressed() {
        XCTAssertEqual(OsxphotosLine.classify("❌️  exiftool error for file /x/FL000013.jpg: Error: Bad MakerNotes offset"),
                       .companionNoise)
        XCTAssertEqual(OsxphotosLine.classify("Retrying export for photo (X: FL000013.jpg)"), .companionNoise)
    }

    func testRealFailureIsExportFailure() {
        let line = "❌️  Error exporting photo (AAA: weird.jpg) as /x/weird.jpg: Error: No space left on device"
        if case .exportFailure(_, let file, let reason) = OsxphotosLine.classify(line) {
            XCTAssertEqual(file, "weird.jpg")
            XCTAssertTrue(reason.contains("No space"))
        } else { XCTFail("expected exportFailure (not a benign embed skip)") }
    }

    func testNormalLineIsOther() {
        XCTAssertEqual(OsxphotosLine.classify("Exporting 78228 photos to /Volumes/PRO-G40/..."), .other)
        XCTAssertEqual(OsxphotosLine.classify("Processed: 78228 photos, exported: 92916, missing: 100, error: 252"), .other)
    }

    func testProgressBarSuppressed() {
        XCTAssertEqual(OsxphotosLine.classify("Exporting 78228 photos ━━━━━━━━ 45% 0:12:34"), .progressBar)
    }

    func testParseReasonTrimsTempPath() {
        XCTAssertEqual(OsxphotosLine.parseReason("foo as /x: Error: Bad MakerNotes offset - /var/folders/abc"),
                       "Bad MakerNotes offset")
    }
}
