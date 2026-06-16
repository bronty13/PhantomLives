import XCTest
@testable import PurplePeek

final class ServicesTests: XCTestCase {

    private var temp: URL!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("pp-svc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temp)
    }

    // MARK: - AudioKeepService

    func testAudioExportCopiesFile() throws {
        let src = temp.appendingPathComponent("song.m4a")
        try Data("audio".utf8).write(to: src)
        let dest = temp.appendingPathComponent("KeptAudio", isDirectory: true)
        let out = try AudioKeepService.export(source: src, to: dest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: src.path)) // original untouched
        XCTAssertEqual(out.lastPathComponent, "song.m4a")
    }

    func testAudioExportDeDuplicatesNames() throws {
        let dest = temp.appendingPathComponent("KeptAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: dest.appendingPathComponent("song.m4a"))
        let src = temp.appendingPathComponent("song.m4a")
        try Data("new".utf8).write(to: src)
        let out = try AudioKeepService.export(source: src, to: dest)
        XCTAssertEqual(out.lastPathComponent, "song 2.m4a")
    }

    func testAudioExportMissingSourceThrows() {
        let dest = temp.appendingPathComponent("KeptAudio", isDirectory: true)
        XCTAssertThrowsError(try AudioKeepService.export(source: temp.appendingPathComponent("nope.m4a"), to: dest))
    }

    // MARK: - DeleteService

    func testDeletePermanentlyRemovesFile() throws {
        let f = temp.appendingPathComponent("doomed.jpg")
        try Data("x".utf8).write(to: f)
        let outcome = DeleteService.deleteFiles([f], permanently: true)
        XCTAssertEqual(outcome.succeeded.count, 1)
        XCTAssertTrue(outcome.failed.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.path))
    }

    func testDeleteMissingFileCountsAsSucceeded() {
        let outcome = DeleteService.deleteFiles([temp.appendingPathComponent("ghost.jpg")], permanently: true)
        XCTAssertEqual(outcome.succeeded.count, 1)
        XCTAssertTrue(outcome.failed.isEmpty)
    }

    // MARK: - MetadataStagingService

    func testStagingMetadataEmptiness() {
        XCTAssertTrue(MetadataStagingService.Metadata(title: nil, caption: nil, keywords: []).isEmpty)
        XCTAssertTrue(MetadataStagingService.Metadata(title: "", caption: "", keywords: []).isEmpty)
        XCTAssertFalse(MetadataStagingService.Metadata(title: "T", caption: nil, keywords: []).isEmpty)
        XCTAssertFalse(MetadataStagingService.Metadata(title: nil, caption: nil, keywords: ["k"]).isEmpty)
    }

    // MARK: - DecisionFilter

    private func file(keep: Int?) -> MediaFile {
        MediaFile(id: "x", scanRoot: "/r", filePath: "/r/x", fileName: "x", fileType: "photo",
                  fileSize: nil, fileModifiedAt: nil, keep: keep, isFavorite: false, title: nil,
                  caption: nil, importedAt: nil, exportedAt: nil, deletedAt: nil,
                  photosAssetId: nil, createdAt: "", updatedAt: "")
    }

    func testDecisionFilterMatches() {
        let undecided = file(keep: nil), kept = file(keep: 1), skipped = file(keep: 0)
        XCTAssertTrue(DecisionFilter.all.matches(undecided))
        XCTAssertTrue(DecisionFilter.undecided.matches(undecided))
        XCTAssertFalse(DecisionFilter.undecided.matches(kept))
        XCTAssertTrue(DecisionFilter.decided.matches(kept))
        XCTAssertTrue(DecisionFilter.decided.matches(skipped))
        XCTAssertFalse(DecisionFilter.decided.matches(undecided))
        XCTAssertTrue(DecisionFilter.kept.matches(kept))
        XCTAssertFalse(DecisionFilter.kept.matches(skipped))
        XCTAssertTrue(DecisionFilter.skipped.matches(skipped))
        XCTAssertFalse(DecisionFilter.skipped.matches(kept))
    }

    // MARK: - Array.chunked

    func testChunked() {
        XCTAssertEqual([1,2,3,4,5].chunked(into: 2), [[1,2],[3,4],[5]])
        XCTAssertEqual([Int]().chunked(into: 2), [])
        XCTAssertEqual([1,2].chunked(into: 10), [[1,2]])
    }
}
