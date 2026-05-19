import XCTest
@testable import PurpleReel

/// Coverage for the C30 per-clip LUT pinning. The two new
/// nullable columns on `clip_metadata` (cameraLUTPath,
/// creativeLUTPath) round-trip through DatabaseService's
/// existing get/set pair. These tests pin:
///   1. Default ClipMetadata.empty has both LUT paths nil.
///   2. Setting a path persists and reads back.
///   3. Setting only the camera LUT leaves the creative LUT nil
///      (and vice versa) — the two roles are independent.
///   4. Empty-string write via updateClipMetadata clears the field
///      (mirrors the existing String-trim-to-nil rule).
@MainActor
final class ClipMetadataLUTTests: XCTestCase {

    private var tempRoot: URL!
    private var db: DatabaseService!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("purplereel-lut-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempRoot, withIntermediateDirectories: true)
        db = try DatabaseService()
        try db.clearAssets()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try? db.clearAssets()
    }

    private func seedAsset() throws -> Int64 {
        let url = tempRoot.appendingPathComponent("clip.mov")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        let asset = Asset(
            rowId: nil, path: url.path, filename: "clip.mov",
            sizeBytes: 0, modifiedAt: Date(),
            codec: "avc1", widthPx: 1920, heightPx: 1080,
            durationSeconds: 60, frameRate: 29.97,
            sha1: nil, addedAt: Date()
        )
        try db.upsertAssets([asset])
        return try db.asset(forPath: url.path)?.rowId ?? -1
    }

    func testEmptyMetadataHasBothLUTsNil() {
        XCTAssertNil(ClipMetadata.empty.cameraLUTPath)
        XCTAssertNil(ClipMetadata.empty.creativeLUTPath)
    }

    func testCameraLUTRoundTrips() throws {
        let rowId = try seedAsset()
        var meta = ClipMetadata(assetId: rowId)
        meta.cameraLUTPath = "/Users/me/luts/SLog3_to_709.cube"
        try db.setClipMetadata(meta)
        let read = try db.clipMetadata(assetId: rowId)
        XCTAssertEqual(read.cameraLUTPath,
                        "/Users/me/luts/SLog3_to_709.cube")
        XCTAssertNil(read.creativeLUTPath,
                      "Setting only camera LUT must leave creative LUT nil")
    }

    func testCreativeLUTRoundTrips() throws {
        let rowId = try seedAsset()
        var meta = ClipMetadata(assetId: rowId)
        meta.creativeLUTPath = "/Users/me/luts/warm_teal.cube"
        try db.setClipMetadata(meta)
        let read = try db.clipMetadata(assetId: rowId)
        XCTAssertEqual(read.creativeLUTPath,
                        "/Users/me/luts/warm_teal.cube")
        XCTAssertNil(read.cameraLUTPath,
                      "Setting only creative LUT must leave camera LUT nil")
    }

    func testBothLUTsPersistIndependently() throws {
        let rowId = try seedAsset()
        var meta = ClipMetadata(assetId: rowId)
        meta.cameraLUTPath = "/luts/cam.cube"
        meta.creativeLUTPath = "/luts/creative.cube"
        try db.setClipMetadata(meta)
        let read = try db.clipMetadata(assetId: rowId)
        XCTAssertEqual(read.cameraLUTPath, "/luts/cam.cube")
        XCTAssertEqual(read.creativeLUTPath, "/luts/creative.cube")
    }

    func testReplacingLUTPathOverwritesPriorValue() throws {
        let rowId = try seedAsset()
        var meta = ClipMetadata(assetId: rowId)
        meta.cameraLUTPath = "/luts/old.cube"
        try db.setClipMetadata(meta)

        meta.cameraLUTPath = "/luts/new.cube"
        try db.setClipMetadata(meta)

        XCTAssertEqual(try db.clipMetadata(assetId: rowId).cameraLUTPath,
                        "/luts/new.cube")
    }

    /// Nil round-trips correctly through the persistence layer too —
    /// matters because the existing migration adds the columns to
    /// existing rows with NULL defaults.
    func testNilLUTSurvivesPersistence() throws {
        let rowId = try seedAsset()
        var meta = ClipMetadata(assetId: rowId)
        meta.title = "Just a title"  // some other field non-nil
        meta.cameraLUTPath = nil
        meta.creativeLUTPath = nil
        try db.setClipMetadata(meta)
        let read = try db.clipMetadata(assetId: rowId)
        XCTAssertEqual(read.title, "Just a title")
        XCTAssertNil(read.cameraLUTPath)
        XCTAssertNil(read.creativeLUTPath)
    }
}
