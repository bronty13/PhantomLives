import XCTest
@testable import PurpleReel

/// `.LP_Store/` sidecar import tests. The Kyno schema isn't
/// formally published; the importer accepts the synonyms seen
/// across forum-archived examples and Kyno-version drift.
@MainActor
final class KynoImportServiceTests: XCTestCase {

    private var tempRoot: URL!
    private var db: DatabaseService!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("purplereel-kyno-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempRoot, withIntermediateDirectories: true)
        // Build the `.LP_Store/` directory once per test under
        // tempRoot — every sidecar XML test writes into it.
        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent(".LP_Store"),
            withIntermediateDirectories: true
        )
        db = try DatabaseService()
        try db.clearAssets()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try? db.clearAssets()
    }

    /// Drop a synthetic media file under `tempRoot` and seed a
    /// matching catalogue row. Returns the rowId.
    private func seedAsset(name: String) throws -> Int64 {
        let url = tempRoot.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data())
        let asset = Asset(
            rowId: nil, path: url.path, filename: name,
            sizeBytes: 0, modifiedAt: Date(),
            codec: "avc1", widthPx: 1920, heightPx: 1080,
            durationSeconds: 30, frameRate: 29.97,
            sha1: nil, addedAt: Date()
        )
        try db.upsertAssets([asset])
        return try db.asset(forPath: url.path)?.rowId ?? -1
    }

    private func writeSidecar(_ xml: String,
                              named: String = "index.xml") throws {
        let dir = tempRoot.appendingPathComponent(".LP_Store")
        try xml.write(to: dir.appendingPathComponent(named),
                      atomically: true, encoding: .utf8)
    }

    // MARK: - Schema-drift synonyms

    func testCanonicalAssetSchemaParsedCorrectly() async throws {
        let rowId = try seedAsset(name: "clip.mov")
        try writeSidecar("""
        <?xml version="1.0" encoding="UTF-8"?>
        <lp_store>
          <asset filename="clip.mov">
            <rating>4</rating>
            <description>Hero close-up</description>
            <tags>
              <tag>hero</tag>
              <tag>day-1</tag>
            </tags>
            <markers>
              <marker time="12.5" note="action!"/>
            </markers>
          </asset>
        </lp_store>
        """)
        let r = await KynoImportService.importTree(root: tempRoot, db: db)
        XCTAssertEqual(r.matched, 1)
        XCTAssertEqual(try db.rating(assetId: rowId)?.stars, 4)
        XCTAssertEqual(try db.tags(assetId: rowId).map(\.name).sorted(),
                       ["day-1", "hero"])
        XCTAssertEqual(try db.markers(assetId: rowId).count, 1)
    }

    func testClipAndStarsSynonymsAreAccepted() async throws {
        let rowId = try seedAsset(name: "clip.mov")
        // Older Kyno versions used `<clip>` + `<stars>`.
        try writeSidecar("""
        <?xml version="1.0" encoding="UTF-8"?>
        <lp_store>
          <clip filename="clip.mov">
            <stars>3</stars>
            <comment>Some note</comment>
            <keyword>setup</keyword>
          </clip>
        </lp_store>
        """)
        let r = await KynoImportService.importTree(root: tempRoot, db: db)
        XCTAssertEqual(r.matched, 1)
        XCTAssertEqual(try db.rating(assetId: rowId)?.stars, 3)
        XCTAssertEqual(try db.tags(assetId: rowId).map(\.name), ["setup"])
        // `<comment>` is a description synonym.
        XCTAssertEqual(try db.clipMetadata(assetId: rowId).description,
                       "Some note")
    }

    func testFilenameInsideChildElementIsAccepted() async throws {
        let rowId = try seedAsset(name: "clip.mov")
        // Some Kyno exports put filename as a child element
        // rather than an attribute.
        try writeSidecar("""
        <?xml version="1.0" encoding="UTF-8"?>
        <lp_store>
          <asset>
            <filename>clip.mov</filename>
            <rating>5</rating>
          </asset>
        </lp_store>
        """)
        let r = await KynoImportService.importTree(root: tempRoot, db: db)
        XCTAssertEqual(r.matched, 1)
        XCTAssertEqual(try db.rating(assetId: rowId)?.stars, 5)
    }

    // MARK: - Rating sanity

    func testRatingClampedToFiveStars() async throws {
        let rowId = try seedAsset(name: "clip.mov")
        try writeSidecar("""
        <?xml version="1.0" encoding="UTF-8"?>
        <lp_store>
          <asset filename="clip.mov">
            <rating>99</rating>
          </asset>
        </lp_store>
        """)
        _ = await KynoImportService.importTree(root: tempRoot, db: db)
        XCTAssertEqual(try db.rating(assetId: rowId)?.stars, 5)
    }

    // MARK: - Unmatched

    func testUnmatchedFilenameReportedAndCatalogueUntouched() async throws {
        // No seedAsset — catalogue is empty.
        try writeSidecar("""
        <?xml version="1.0" encoding="UTF-8"?>
        <lp_store>
          <asset filename="ghost.mov">
            <rating>5</rating>
          </asset>
        </lp_store>
        """)
        let r = await KynoImportService.importTree(root: tempRoot, db: db)
        XCTAssertEqual(r.matched, 0)
        XCTAssertEqual(r.skipped, 1)
        XCTAssertTrue(r.unmatchedFilenames.contains("ghost.mov"))
        XCTAssertEqual((try db.allAssets()).count, 0)
    }

    // MARK: - Discovery

    func testKynoLegacyDirectoryNameIsAlsoWalked() async throws {
        // Older Kyno versions used `.kyno/` instead of `.LP_Store/`.
        // Importer should walk both.
        try FileManager.default.removeItem(
            at: tempRoot.appendingPathComponent(".LP_Store")
        )
        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent(".kyno"),
            withIntermediateDirectories: true
        )
        let rowId = try seedAsset(name: "clip.mov")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <lp_store>
          <asset filename="clip.mov">
            <rating>2</rating>
          </asset>
        </lp_store>
        """.write(
            to: tempRoot.appendingPathComponent(".kyno/index.xml"),
            atomically: true, encoding: .utf8
        )
        let r = await KynoImportService.importTree(root: tempRoot, db: db)
        XCTAssertEqual(r.sidecarsFound, 1)
        XCTAssertEqual(r.matched, 1)
        XCTAssertEqual(try db.rating(assetId: rowId)?.stars, 2)
    }
}
