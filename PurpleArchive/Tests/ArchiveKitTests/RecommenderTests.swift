import XCTest
@testable import ArchiveKit

final class RecommenderTests: XCTestCase {

    func testEncryptionForcesZip() {
        let rec = FormatRecommender.recommend(
            inputs: [], constraints: .init(needsEncryption: true))
        XCTAssertEqual(rec.format, .zip)
    }

    func testWindowsCompatForcesZip() {
        let rec = FormatRecommender.recommend(
            inputs: [], constraints: .init(needsWindowsCompatibility: true))
        XCTAssertEqual(rec.format, .zip)
    }

    func testMaxCompressionPicksXz() {
        let rec = FormatRecommender.recommend(
            inputs: [], constraints: .init(prioritizeMaxCompression: true))
        XCTAssertEqual(rec.format, .tarXz)
    }

    func testDefaultIsZstd() {
        let rec = FormatRecommender.recommend(inputs: [], constraints: .init())
        XCTAssertEqual(rec.format, .tarZst)
    }

    func testAlreadyCompressedMediaAvoidsRecompression() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        // A folder of already-compressed media.
        for n in ["a.jpg", "b.mp4", "c.png", "d.mp3"] {
            try Data("x".utf8).write(to: tmp.appendingPathComponent(n))
        }
        let (count, mostly) = FormatRecommender.analyze([tmp])
        XCTAssertEqual(count, 4)
        XCTAssertTrue(mostly)
    }
}

final class WindowsSafeNamerTests: XCTestCase {

    func testReservedCharsReplaced() {
        XCTAssertEqual(WindowsSafeNamer.sanitizeComponent("a:b*c?.txt"), "a_b_c_.txt")
    }

    func testTrailingDotsAndSpacesTrimmed() {
        XCTAssertEqual(WindowsSafeNamer.sanitizeComponent("name.  "), "name")
        XCTAssertEqual(WindowsSafeNamer.sanitizeComponent("dir..."), "dir")
    }

    func testReservedDeviceNames() {
        XCTAssertEqual(WindowsSafeNamer.sanitizeComponent("CON"), "_CON")
        XCTAssertEqual(WindowsSafeNamer.sanitizeComponent("nul.txt"), "_nul.txt")
        XCTAssertEqual(WindowsSafeNamer.sanitizeComponent("COM1"), "_COM1")
    }

    func testSafeNamesUnchanged() {
        XCTAssertTrue(WindowsSafeNamer.isSafe("normal_file-1.txt"))
        XCTAssertEqual(WindowsSafeNamer.sanitizePath("a/b/c.txt"), "a/b/c.txt")
    }

    func testPathSanitizedComponentwise() {
        XCTAssertEqual(WindowsSafeNamer.sanitizePath("ok/bad:name/CON.txt"),
                       "ok/bad_name/_CON.txt")
    }
}
