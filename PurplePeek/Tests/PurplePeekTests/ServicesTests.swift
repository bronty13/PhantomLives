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

    func testPhotoExiftoolArgsUseXMPAndIPTCListTags() {
        let meta = MetadataStagingService.Metadata(title: "T", caption: "C", keywords: ["k1", "k2"])
        let args = MetadataStagingService.exiftoolArgs(kind: .photo, metadata: meta, path: "/tmp/p.jpg")
        XCTAssertTrue(args.contains("-XMP:Title=T"))
        XCTAssertTrue(args.contains("-IPTC:ObjectName=T"))
        XCTAssertTrue(args.contains("-IPTC:Caption-Abstract=C"))
        XCTAssertTrue(args.contains("-XMP-dc:Description=C"))
        // List tags: one -TAG= per keyword (exiftool accumulates these into a list).
        XCTAssertTrue(args.contains("-IPTC:Keywords=k1"))
        XCTAssertTrue(args.contains("-IPTC:Keywords=k2"))
        XCTAssertTrue(args.contains("-XMP-dc:Subject=k1"))
        // Photos must never get the QuickTime Keys: group.
        XCTAssertFalse(args.contains { $0.hasPrefix("-Keys:") })
        XCTAssertEqual(args.last, "/tmp/p.jpg")
    }

    func testVideoExiftoolArgsUseKeysGroupWithCommaJoinedKeywords() {
        let meta = MetadataStagingService.Metadata(title: "T", caption: "C", keywords: ["k1", "k2", "k3"])
        let args = MetadataStagingService.exiftoolArgs(kind: .video, metadata: meta, path: "/tmp/v.mp4")
        XCTAssertTrue(args.contains("-Keys:Title=T"))
        XCTAssertTrue(args.contains("-Keys:Description=C"))
        // Keys:Keywords is NOT a list tag — keywords go in as ONE comma-joined string
        // (Photos splits it back into individual keywords on import; verified 2026-06-18).
        XCTAssertTrue(args.contains("-Keys:Keywords=k1,k2,k3"))
        // DisplayName must NOT be set — it would override Keys:Title in Photos.
        XCTAssertFalse(args.contains { $0.hasPrefix("-Keys:DisplayName") })
        // Videos must never get the still-image XMP/IPTC tags.
        XCTAssertFalse(args.contains { $0.hasPrefix("-XMP") || $0.hasPrefix("-IPTC") || $0.hasPrefix("-EXIF") })
        XCTAssertEqual(args.last, "/tmp/v.mp4")
    }

    func testExiftoolArgsOmitEmptyFields() {
        let meta = MetadataStagingService.Metadata(title: nil, caption: "", keywords: [""])
        let photo = MetadataStagingService.exiftoolArgs(kind: .photo, metadata: meta, path: "/tmp/p.jpg")
        let video = MetadataStagingService.exiftoolArgs(kind: .video, metadata: meta, path: "/tmp/v.mp4")
        // Nothing to embed → only the leading charset flags + the path.
        XCTAssertFalse(photo.contains { $0.hasPrefix("-XMP") || $0.hasPrefix("-IPTC") })
        XCTAssertFalse(video.contains { $0.hasPrefix("-Keys:") })
    }

    // MARK: - FileHashService

    func testFileHashIdenticalContentMatches() throws {
        let a = temp.appendingPathComponent("a.bin")
        let b = temp.appendingPathComponent("b.bin")   // same bytes, different name
        let c = temp.appendingPathComponent("c.bin")   // different bytes
        try Data("the same exact bytes".utf8).write(to: a)
        try Data("the same exact bytes".utf8).write(to: b)
        try Data("totally different bytes".utf8).write(to: c)

        let ha = FileHashService.sha256(of: a)
        XCTAssertNotNil(ha)
        XCTAssertEqual(ha, FileHashService.sha256(of: b))      // identical content → same hash
        XCTAssertNotEqual(ha, FileHashService.sha256(of: c))   // different content → different hash
    }

    func testFileHashMissingFileIsNil() {
        XCTAssertNil(FileHashService.sha256(of: temp.appendingPathComponent("nope.bin")))
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
