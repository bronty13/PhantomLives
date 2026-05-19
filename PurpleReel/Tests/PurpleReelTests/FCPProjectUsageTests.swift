import XCTest
@testable import PurpleReel

/// Coverage for the C25 FCP project-membership import. Reuses the
/// FCPXMLImportServiceTests fixture pattern (temp DB seeded with a
/// known asset row, synthetic FCPXML written next to it, importer
/// run end-to-end). Tests pin the parser's behavior in the
/// presence of `<event>` and `<project>` containers around the
/// clip refs.
@MainActor
final class FCPProjectUsageTests: XCTestCase {

    private var tempRoot: URL!
    private var db: DatabaseService!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("purplereel-fcp-usage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempRoot, withIntermediateDirectories: true)
        db = try DatabaseService()
        try db.clearAssets()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        try? db.clearAssets()
    }

    private func seedAsset(name: String) throws -> Int64 {
        let url = tempRoot.appendingPathComponent(name)
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

    private func percentPath(_ name: String) -> String {
        tempRoot.appendingPathComponent(name).path
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
    }

    // MARK: - Project / event capture

    func testClipInsideProjectRecordsUsageRow() async throws {
        let rowId = try seedAsset(name: "clip.mov")
        let p = percentPath("clip.mov")
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fcpxml version="1.10">
          <resources>
            <asset id="r1" name="clip.mov" duration="3600s" start="0s">
              <media-rep kind="original-media" src="file://\(p)"/>
            </asset>
          </resources>
          <event name="My Event">
            <project name="My Project">
              <sequence>
                <asset-clip ref="r1" name="clip.mov" offset="0s" start="0s" duration="3600s"/>
              </sequence>
            </project>
          </event>
        </fcpxml>
        """
        let result = await FCPXMLImportService.importXML(
            at: try writeXML(xml), db: db
        )
        XCTAssertEqual(result.matchedClips, 1)
        XCTAssertEqual(result.projectUsageRecorded, 1)

        let usage = try db.fcpProjectUsage(assetId: rowId)
        XCTAssertEqual(usage.count, 1)
        XCTAssertEqual(usage.first?.projectName, "My Project")
        XCTAssertEqual(usage.first?.eventName, "My Event")
    }

    /// Clips that sit directly under an `<event>` without an
    /// enclosing `<project>` (FCP's "event browser" layout) must
    /// NOT record a usage row — they're not part of a project.
    func testClipOutsideProjectDoesNotRecordUsage() async throws {
        let rowId = try seedAsset(name: "clip.mov")
        let p = percentPath("clip.mov")
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fcpxml version="1.10">
          <resources>
            <asset id="r1" name="clip.mov" duration="3600s" start="0s">
              <media-rep kind="original-media" src="file://\(p)"/>
            </asset>
          </resources>
          <event name="Bare Event">
            <asset-clip ref="r1" name="clip.mov" offset="0s" start="0s" duration="3600s"/>
          </event>
        </fcpxml>
        """
        let result = await FCPXMLImportService.importXML(
            at: try writeXML(xml), db: db
        )
        XCTAssertEqual(result.matchedClips, 1)
        XCTAssertEqual(result.projectUsageRecorded, 0,
                        "Bare event without <project> should not record usage")
        let usage = try db.fcpProjectUsage(assetId: rowId)
        XCTAssertTrue(usage.isEmpty)
    }

    /// Re-importing the same FCPXML upserts on the (assetId,
    /// projectName) composite key — refreshing `importedAt` but
    /// not creating duplicate rows.
    func testReimportingSameFCPXMLIsIdempotent() async throws {
        let rowId = try seedAsset(name: "clip.mov")
        let p = percentPath("clip.mov")
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fcpxml version="1.10">
          <resources>
            <asset id="r1" name="clip.mov" duration="3600s" start="0s">
              <media-rep kind="original-media" src="file://\(p)"/>
            </asset>
          </resources>
          <event name="E">
            <project name="P">
              <sequence>
                <asset-clip ref="r1" name="clip.mov" offset="0s" start="0s" duration="3600s"/>
              </sequence>
            </project>
          </event>
        </fcpxml>
        """
        let url = try writeXML(xml)
        _ = await FCPXMLImportService.importXML(at: url, db: db)
        _ = await FCPXMLImportService.importXML(at: url, db: db)
        XCTAssertEqual(try db.fcpProjectUsage(assetId: rowId).count, 1,
                        "Re-importing should upsert rather than duplicate")
    }

    /// Same asset referenced from two different projects (in
    /// different FCPXML files) should accumulate both rows.
    func testTwoDifferentProjectsBothRecorded() async throws {
        let rowId = try seedAsset(name: "clip.mov")
        let p = percentPath("clip.mov")

        let xml1 = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fcpxml version="1.10">
          <resources>
            <asset id="r1" name="clip.mov" duration="3600s" start="0s">
              <media-rep kind="original-media" src="file://\(p)"/>
            </asset>
          </resources>
          <event name="E1">
            <project name="Project A">
              <sequence><asset-clip ref="r1" name="clip.mov" offset="0s" start="0s" duration="3600s"/></sequence>
            </project>
          </event>
        </fcpxml>
        """
        let xml2 = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fcpxml version="1.10">
          <resources>
            <asset id="r1" name="clip.mov" duration="3600s" start="0s">
              <media-rep kind="original-media" src="file://\(p)"/>
            </asset>
          </resources>
          <event name="E2">
            <project name="Project B">
              <sequence><asset-clip ref="r1" name="clip.mov" offset="0s" start="0s" duration="3600s"/></sequence>
            </project>
          </event>
        </fcpxml>
        """

        let url1 = tempRoot.appendingPathComponent("p1.fcpxml")
        let url2 = tempRoot.appendingPathComponent("p2.fcpxml")
        try xml1.write(to: url1, atomically: true, encoding: .utf8)
        try xml2.write(to: url2, atomically: true, encoding: .utf8)
        _ = await FCPXMLImportService.importXML(at: url1, db: db)
        _ = await FCPXMLImportService.importXML(at: url2, db: db)

        let usage = try db.fcpProjectUsage(assetId: rowId)
        XCTAssertEqual(usage.count, 2)
        let names = Set(usage.map(\.projectName))
        XCTAssertEqual(names, ["Project A", "Project B"])
    }

    /// libraryPath on the usage row should reflect the FCPXML file
    /// the importer read, not the underlying .fcpbundle (PurpleReel
    /// doesn't introspect those — by design).
    func testLibraryPathCapturesFCPXMLFileURL() async throws {
        let rowId = try seedAsset(name: "clip.mov")
        let p = percentPath("clip.mov")
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <fcpxml version="1.10">
          <resources>
            <asset id="r1" name="clip.mov" duration="3600s" start="0s">
              <media-rep kind="original-media" src="file://\(p)"/>
            </asset>
          </resources>
          <event name="E"><project name="P">
            <sequence><asset-clip ref="r1" name="clip.mov" offset="0s" start="0s" duration="3600s"/></sequence>
          </project></event>
        </fcpxml>
        """
        let url = try writeXML(xml)
        _ = await FCPXMLImportService.importXML(at: url, db: db)
        let usage = try db.fcpProjectUsage(assetId: rowId).first
        XCTAssertEqual(usage?.libraryPath, url.path)
    }
}
