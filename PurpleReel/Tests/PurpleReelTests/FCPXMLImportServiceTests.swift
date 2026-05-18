import XCTest
@testable import PurpleReel

/// FCPXML re-import round-trip (Kyno-parity row 5). These tests
/// exercise the parser + merge logic against synthetic XML
/// fixtures that mirror what FCP / Premiere actually emit.
@MainActor
final class FCPXMLImportServiceTests: XCTestCase {

    // MARK: - Fixture infra
    //
    // Each test spins up an isolated DatabaseService backed by a
    // temp-directory SQLite file, scans in one or two synthetic
    // assets, writes an FCPXML to a temp path, and runs the
    // importer end-to-end. Cleanup via tearDown.

    private var tempRoot: URL!
    private var db: DatabaseService!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("purplereel-fcpxml-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempRoot, withIntermediateDirectories: true)
        // The DB constructor anchors at Application Support;
        // there's no path override. For unit tests we just use it
        // as the shared instance — each test cleans up the rows
        // it inserts.
        db = try DatabaseService()
        try db.clearAssets()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try? db.clearAssets()
    }

    /// Seed one asset row matching `name` so the FCPXML importer
    /// has something to merge into. Returns the rowId.
    private func seedAsset(name: String) throws -> Int64 {
        let url = tempRoot.appendingPathComponent(name)
        // Touch the file so file-exists checks pass downstream.
        FileManager.default.createFile(atPath: url.path, contents: Data())
        let asset = Asset(
            rowId: nil,
            path: url.path,
            filename: name,
            sizeBytes: 0,
            modifiedAt: Date(),
            codec: "avc1",
            widthPx: 1920, heightPx: 1080,
            durationSeconds: 60, frameRate: 29.97,
            sha1: nil,
            addedAt: Date()
        )
        try db.upsertAssets([asset])
        guard let stored = try db.asset(forPath: url.path),
              let rowId = stored.rowId else {
            XCTFail("seedAsset failed for \(name)")
            return -1
        }
        return rowId
    }

    private func writeXML(_ body: String) throws -> URL {
        let url = tempRoot.appendingPathComponent("project.fcpxml")
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Parsing — rational time strings

    func testMarkerWithRationalTimeIsImportedAtCorrectSeconds() async throws {
        let rowId = try seedAsset(name: "clip.mov")
        // 6006/30000 = 0.2002 seconds. Standard FCP form for
        // 29.97-base content.
        let path = tempRoot.appendingPathComponent("clip.mov").path
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fcpxml version="1.10">
          <resources>
            <asset id="r1" name="clip.mov" duration="3600s" start="0s">
              <media-rep kind="original-media" src="file://\(path)"/>
            </asset>
          </resources>
          <event name="Test">
            <asset-clip ref="r1" name="clip.mov" offset="0s" start="0s" duration="3600s">
              <marker start="6006/30000s" duration="1001/30000s" value="action"/>
            </asset-clip>
          </event>
        </fcpxml>
        """
        let result = await FCPXMLImportService.importXML(
            at: try writeXML(xml), db: db
        )
        XCTAssertEqual(result.matchedClips, 1)
        XCTAssertEqual(result.markersAdded, 1)
        let markers = try db.markers(assetId: rowId)
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers[0].timecodeIn, 0.2002, accuracy: 0.001)
        XCTAssertEqual(markers[0].note, "action")
    }

    func testMarkerWithPlainSecondsIsImportedAtCorrectSeconds() async throws {
        let rowId = try seedAsset(name: "clip.mov")
        let path = tempRoot.appendingPathComponent("clip.mov").path
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fcpxml version="1.10">
          <resources>
            <asset id="r1" name="clip.mov" duration="3600s" start="0s">
              <media-rep kind="original-media" src="file://\(path)"/>
            </asset>
          </resources>
          <event name="Test">
            <asset-clip ref="r1" name="clip.mov" offset="0s" start="0s" duration="3600s">
              <marker start="3.5s" duration="1s" value="cut here"/>
            </asset-clip>
          </event>
        </fcpxml>
        """
        let r = await FCPXMLImportService.importXML(
            at: try writeXML(xml), db: db
        )
        XCTAssertEqual(r.markersAdded, 1)
        let markers = try db.markers(assetId: rowId)
        XCTAssertEqual(markers[0].timecodeIn, 3.5, accuracy: 0.001)
    }

    // MARK: - Additive merge — markers de-dupe

    func testReImportOfSameMarkerIsSkipped() async throws {
        let rowId = try seedAsset(name: "clip.mov")
        let path = tempRoot.appendingPathComponent("clip.mov").path
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fcpxml version="1.10">
          <resources>
            <asset id="r1" name="clip.mov" duration="3600s" start="0s">
              <media-rep kind="original-media" src="file://\(path)"/>
            </asset>
          </resources>
          <event name="Test">
            <asset-clip ref="r1" name="clip.mov" offset="0s" start="0s" duration="3600s">
              <marker start="3s" duration="1s" value="same note"/>
            </asset-clip>
          </event>
        </fcpxml>
        """
        // Run twice.
        _ = await FCPXMLImportService.importXML(
            at: try writeXML(xml), db: db
        )
        let r2 = await FCPXMLImportService.importXML(
            at: try writeXML(xml), db: db
        )
        XCTAssertEqual(r2.markersAdded, 0)
        XCTAssertEqual(r2.markersSkipped, 1)
        XCTAssertEqual(try db.markers(assetId: rowId).count, 1,
            "Second import must not double the marker count")
    }

    // MARK: - Keywords → tags

    func testCommaSeparatedKeywordsBecomeIndividualTags() async throws {
        let rowId = try seedAsset(name: "clip.mov")
        let path = tempRoot.appendingPathComponent("clip.mov").path
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fcpxml version="1.10">
          <resources>
            <asset id="r1" name="clip.mov" duration="3600s" start="0s">
              <media-rep kind="original-media" src="file://\(path)"/>
            </asset>
          </resources>
          <event name="Test">
            <asset-clip ref="r1" name="clip.mov" offset="0s" start="0s" duration="3600s">
              <keyword start="0s" duration="60s" value="hero, day-1, alpha"/>
            </asset-clip>
          </event>
        </fcpxml>
        """
        let r = await FCPXMLImportService.importXML(
            at: try writeXML(xml), db: db
        )
        XCTAssertEqual(r.tagsAdded, 3)
        let names = Set(try db.tags(assetId: rowId).map(\.name))
        XCTAssertEqual(names, ["hero", "day-1", "alpha"])
    }

    // MARK: - Rating — favorite only raises

    func testFavoriteRaisesRatingToFiveStars() async throws {
        let rowId = try seedAsset(name: "clip.mov")
        let path = tempRoot.appendingPathComponent("clip.mov").path
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fcpxml version="1.10">
          <resources>
            <asset id="r1" name="clip.mov" duration="3600s" start="0s">
              <media-rep kind="original-media" src="file://\(path)"/>
            </asset>
          </resources>
          <event name="Test">
            <asset-clip ref="r1" name="clip.mov" offset="0s" start="0s" duration="3600s">
              <rating name="Favorite" start="0s" duration="3600s" value="favorite"/>
            </asset-clip>
          </event>
        </fcpxml>
        """
        let r = await FCPXMLImportService.importXML(
            at: try writeXML(xml), db: db
        )
        XCTAssertEqual(r.ratingsApplied, 1)
        XCTAssertEqual(try db.rating(assetId: rowId)?.stars, 5)
    }

    func testFavoriteDoesNotDemoteExistingFiveStarRating() async throws {
        let rowId = try seedAsset(name: "clip.mov")
        // Pre-rate at 5 (the user already loved this clip before
        // the editor confirmed it as Favorite in FCP).
        try db.setRating(assetId: rowId, stars: 5,
                         colorLabel: nil, description: nil)
        let path = tempRoot.appendingPathComponent("clip.mov").path
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fcpxml version="1.10">
          <resources>
            <asset id="r1" name="clip.mov" duration="3600s" start="0s">
              <media-rep kind="original-media" src="file://\(path)"/>
            </asset>
          </resources>
          <event name="Test">
            <asset-clip ref="r1" name="clip.mov" offset="0s" start="0s" duration="3600s">
              <rating name="Favorite" start="0s" duration="3600s" value="favorite"/>
            </asset-clip>
          </event>
        </fcpxml>
        """
        let r = await FCPXMLImportService.importXML(
            at: try writeXML(xml), db: db
        )
        XCTAssertEqual(r.ratingsApplied, 0,
            "Should not be reported as applied since rating was already at the ceiling")
        XCTAssertEqual(try db.rating(assetId: rowId)?.stars, 5)
    }

    // MARK: - Metadata — fill empty slots only

    func testMetadataFillsEmptyLogFields() async throws {
        let rowId = try seedAsset(name: "clip.mov")
        let path = tempRoot.appendingPathComponent("clip.mov").path
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fcpxml version="1.10">
          <resources>
            <asset id="r1" name="clip.mov" duration="3600s" start="0s">
              <media-rep kind="original-media" src="file://\(path)"/>
            </asset>
          </resources>
          <event name="Test">
            <asset-clip ref="r1" name="clip.mov" offset="0s" start="0s" duration="3600s">
              <metadata>
                <md key="Scene" value="14A"/>
                <md key="Take" value="3"/>
                <md key="Camera" value="Sony FX3"/>
              </metadata>
            </asset-clip>
          </event>
        </fcpxml>
        """
        _ = await FCPXMLImportService.importXML(
            at: try writeXML(xml), db: db
        )
        let meta = try db.clipMetadata(assetId: rowId)
        XCTAssertEqual(meta.scene, "14A")
        XCTAssertEqual(meta.take, "3")
        XCTAssertEqual(meta.camera, "Sony FX3")
    }

    func testMetadataDoesNotOverwriteExistingLogField() async throws {
        let rowId = try seedAsset(name: "clip.mov")
        // User already wrote "Local scene 7" before importing
        // FCP's edits. The import should NOT clobber it.
        var meta = try db.clipMetadata(assetId: rowId)
        meta.scene = "Local scene 7"
        try db.setClipMetadata(meta)
        let path = tempRoot.appendingPathComponent("clip.mov").path
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fcpxml version="1.10">
          <resources>
            <asset id="r1" name="clip.mov" duration="3600s" start="0s">
              <media-rep kind="original-media" src="file://\(path)"/>
            </asset>
          </resources>
          <event name="Test">
            <asset-clip ref="r1" name="clip.mov" offset="0s" start="0s" duration="3600s">
              <metadata>
                <md key="Scene" value="Editor's scene"/>
              </metadata>
            </asset-clip>
          </event>
        </fcpxml>
        """
        _ = await FCPXMLImportService.importXML(
            at: try writeXML(xml), db: db
        )
        XCTAssertEqual(try db.clipMetadata(assetId: rowId).scene, "Local scene 7",
            "Existing user-set Scene must survive the import")
    }

    // MARK: - Unmatched assets

    func testUnmatchedAssetIsReportedAndNotInserted() async throws {
        // No seedAsset() — the catalogue is empty.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fcpxml version="1.10">
          <resources>
            <asset id="r1" name="ghost.mov" duration="3600s" start="0s">
              <media-rep kind="original-media" src="file:///tmp/ghost.mov"/>
            </asset>
          </resources>
          <event name="Test">
            <asset-clip ref="r1" name="ghost.mov" offset="0s" start="0s" duration="3600s">
              <marker start="3s" duration="1s" value="x"/>
            </asset-clip>
          </event>
        </fcpxml>
        """
        let r = await FCPXMLImportService.importXML(
            at: try writeXML(xml), db: db
        )
        XCTAssertEqual(r.matchedClips, 0)
        XCTAssertEqual(r.markersAdded, 0)
        XCTAssertTrue(r.unmatchedFilenames.contains("ghost.mov"))
        // Critically, no new asset row was created.
        XCTAssertEqual((try db.allAssets()).count, 0)
    }
}
