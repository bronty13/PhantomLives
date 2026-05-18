import XCTest
@testable import PurpleReel

/// Regression coverage for the GRDB-`insert(db)`-doesn't-populate-id
/// trap. GRDB's `PersistableRecord.insert(_:)` is non-mutating; the
/// inserted record's `id` stays `nil`. `addTag` hit this in
/// production (silent no-op for brand-new tag names). `addMarker`
/// + `addSubclip` had the same pattern with currently-discarded
/// return values — fixed preemptively. These tests pin the
/// returned `.id` so any future regression on insert-and-return
/// surfaces immediately.
final class DatabaseServiceInsertIDTests: XCTestCase {

    private var db: DatabaseService!

    override func setUpWithError() throws {
        db = try DatabaseService()
        try db.clearAssets()
    }

    override func tearDownWithError() throws {
        try? db.clearAssets()
    }

    /// Seed a single asset row and return its rowId — needed
    /// because marker / subclip / asset_tag inserts all reference
    /// an asset id via foreign key.
    private func seedAsset(filename: String = "clip.mov") throws -> Int64 {
        let path = "/tmp/purplereel-tests/\(UUID().uuidString)/\(filename)"
        let asset = Asset(
            rowId: nil, path: path, filename: filename,
            sizeBytes: 0, modifiedAt: Date(),
            codec: "avc1", widthPx: 1920, heightPx: 1080,
            durationSeconds: 30, frameRate: 29.97,
            sha1: nil, addedAt: Date()
        )
        try db.upsertAssets([asset])
        guard let rowId = try db.asset(forPath: path)?.rowId else {
            XCTFail("seedAsset failed")
            return -1
        }
        return rowId
    }

    // MARK: - addTag

    func testAddTagReturnsTagWithPopulatedId() throws {
        let assetId = try seedAsset()
        let tag = try db.addTag(name: "regression-test-\(UUID().uuidString)",
                                 assetId: assetId)
        XCTAssertNotNil(tag.id,
            "addTag must return Tag with id populated — this is the latent bug fixed")
    }

    func testAddTagIsIdempotentAcrossRepeatCalls() throws {
        let assetId = try seedAsset()
        let name = "regression-tag-\(UUID().uuidString)"
        let t1 = try db.addTag(name: name, assetId: assetId)
        let t2 = try db.addTag(name: name, assetId: assetId)
        XCTAssertEqual(t1.id, t2.id,
            "Same tag name should resolve to the same row across calls")
    }

    func testAddTagCreatesAssetTagLinkForNewTag() throws {
        let assetId = try seedAsset()
        let name = "regression-tag-link-\(UUID().uuidString)"
        _ = try db.addTag(name: name, assetId: assetId)
        let names = try db.tags(assetId: assetId).map(\.name)
        XCTAssertTrue(names.contains(name),
            "asset_tag link must be created on first addTag — pre-fix this failed silently")
    }

    // MARK: - addMarker

    func testAddMarkerReturnsMarkerWithPopulatedId() throws {
        let assetId = try seedAsset()
        let marker = try db.addMarker(
            assetId: assetId, timecodeIn: 12.5, note: "test marker"
        )
        XCTAssertNotNil(marker.id,
            "addMarker must return Marker with id populated")
    }

    func testAddMarkerPersistsAllFieldsCorrectly() throws {
        let assetId = try seedAsset()
        let returned = try db.addMarker(
            assetId: assetId,
            timecodeIn: 12.5,
            timecodeOut: 18.25,
            note: "Action!"
        )
        // Round-trip via fetch — confirms the returned record's id
        // actually points at a real DB row with the right values.
        let fetched = try db.markers(assetId: assetId)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, returned.id)
        XCTAssertEqual(fetched[0].timecodeIn, 12.5, accuracy: 0.001)
        XCTAssertEqual(fetched[0].timecodeOut ?? 0, 18.25, accuracy: 0.001)
        XCTAssertEqual(fetched[0].note, "Action!")
    }

    func testTwoMarkersOnSameAssetGetDistinctIds() throws {
        let assetId = try seedAsset()
        let m1 = try db.addMarker(assetId: assetId, timecodeIn: 1.0)
        let m2 = try db.addMarker(assetId: assetId, timecodeIn: 2.0)
        XCTAssertNotNil(m1.id)
        XCTAssertNotNil(m2.id)
        XCTAssertNotEqual(m1.id, m2.id,
            "Each insert must produce a unique autoincrement id")
    }

    // MARK: - addSubclip

    func testAddSubclipReturnsSubclipWithPopulatedId() throws {
        let assetId = try seedAsset()
        let s = try db.addSubclip(
            parentAssetId: assetId, name: "take 3",
            timecodeIn: 5.0, timecodeOut: 12.5
        )
        XCTAssertNotNil(s.id,
            "addSubclip must return Subclip with id populated")
    }

    func testAddSubclipPersistsAllFieldsCorrectly() throws {
        let assetId = try seedAsset()
        let returned = try db.addSubclip(
            parentAssetId: assetId, name: "good take",
            timecodeIn: 5.0, timecodeOut: 12.5
        )
        let fetched = try db.subclips(parentAssetId: assetId)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, returned.id)
        XCTAssertEqual(fetched[0].name, "good take")
        XCTAssertEqual(fetched[0].timecodeIn, 5.0, accuracy: 0.001)
        XCTAssertEqual(fetched[0].timecodeOut, 12.5, accuracy: 0.001)
    }

    func testTwoSubclipsOnSameAssetGetDistinctIds() throws {
        let assetId = try seedAsset()
        let s1 = try db.addSubclip(
            parentAssetId: assetId, name: "a",
            timecodeIn: 0, timecodeOut: 5
        )
        let s2 = try db.addSubclip(
            parentAssetId: assetId, name: "b",
            timecodeIn: 10, timecodeOut: 15
        )
        XCTAssertNotNil(s1.id)
        XCTAssertNotNil(s2.id)
        XCTAssertNotEqual(s1.id, s2.id)
    }
}
