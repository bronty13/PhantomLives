import XCTest
@testable import PurpleReel

/// Shared workspace cache (Kyno-parity row 7) — sidecar JSON
/// round-trip + freshness gate + additive hydrate semantics.
@MainActor
final class WorkspaceCacheServiceTests: XCTestCase {

    private var tempRoot: URL!
    private let defaultsKey = WorkspaceCacheService.enabledDefaultsKey

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("purplereel-wcache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private func touchFile(_ name: String) -> URL {
        let url = tempRoot.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data())
        return url
    }

    private func samplePayload(for url: URL) -> WorkspaceCacheService.Payload {
        let attrs = (try? FileManager.default.attributesOfItem(
            atPath: url.path)) ?? [:]
        let mod = (attrs[.modificationDate] as? Date) ?? Date()
        return WorkspaceCacheService.Payload(
            filename: url.lastPathComponent,
            sizeBytes: 1234,
            modifiedAt: mod,
            tech: .init(
                codec: "hvc1", widthPx: 3840, heightPx: 2160,
                durationSeconds: 60, frameRate: 29.97,
                audioCodec: "aac ", recordedAt: nil, createdAt: nil,
                isVFR: false, sha1: nil, posterFrameSeconds: 12.5
            ),
            user: .init(
                ratingStars: 4,
                tags: ["hero", "day-1"],
                title: "Hero close-up",
                description: nil, reel: nil, scene: nil, shot: nil,
                take: nil, angle: nil, camera: nil
            ),
            markers: [],
            subclips: []
        )
    }

    // MARK: - Path conventions

    func testSidecarURLLivesInPurplereelSubdirectoryNextToAsset() {
        let url = URL(fileURLWithPath: "/Volumes/CardA/clip.mov")
        let sidecar = WorkspaceCacheService.sidecarURL(for: url.path)
        XCTAssertEqual(sidecar.path,
                        "/Volumes/CardA/.purplereel/clip.mov.json")
    }

    // MARK: - Write gating

    func testWriteIsNoopWhenToggleIsOff() {
        UserDefaults.standard.set(false, forKey: defaultsKey)
        let url = touchFile("clip.mov")
        let payload = samplePayload(for: url)
        WorkspaceCacheService.writePayload(payload, for: url.path)
        let sidecar = WorkspaceCacheService.sidecarURL(for: url.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.path),
            "Sidecar must not be written when the toggle is off")
    }

    func testWriteSucceedsWhenToggleIsOn() {
        UserDefaults.standard.set(true, forKey: defaultsKey)
        let url = touchFile("clip.mov")
        let payload = samplePayload(for: url)
        WorkspaceCacheService.writePayload(payload, for: url.path)
        let sidecar = WorkspaceCacheService.sidecarURL(for: url.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path))
    }

    // MARK: - Round-trip

    func testPayloadRoundTrips() throws {
        UserDefaults.standard.set(true, forKey: defaultsKey)
        let url = touchFile("clip.mov")
        let original = samplePayload(for: url)
        WorkspaceCacheService.writePayload(original, for: url.path)
        guard let decoded = WorkspaceCacheService.loadIfFresh(for: url.path)
        else {
            XCTFail("Sidecar should load back after write")
            return
        }
        XCTAssertEqual(decoded.filename, original.filename)
        XCTAssertEqual(decoded.sizeBytes, original.sizeBytes)
        XCTAssertEqual(decoded.tech.codec, "hvc1")
        XCTAssertEqual(decoded.tech.posterFrameSeconds, 12.5)
        XCTAssertEqual(decoded.user.ratingStars, 4)
        XCTAssertEqual(decoded.user.tags, ["hero", "day-1"])
        XCTAssertEqual(decoded.user.title, "Hero close-up")
    }

    // MARK: - Freshness gate

    func testLoadReturnsNilWhenModtimeDiffersBeyondTolerance() throws {
        UserDefaults.standard.set(true, forKey: defaultsKey)
        let url = touchFile("clip.mov")
        var payload = samplePayload(for: url)
        // Force the sidecar's modtime to be 1 hour off — far
        // outside the ±1-second freshness tolerance.
        payload.modifiedAt = payload.modifiedAt.addingTimeInterval(3600)
        WorkspaceCacheService.writePayload(payload, for: url.path)
        // Reader gates on modtime match — file's real modtime
        // hasn't changed, so the encoded one is stale.
        XCTAssertNil(WorkspaceCacheService.loadIfFresh(for: url.path),
            "Sidecar with mismatched modtime must not load")
    }

    func testLoadReturnsNilWhenSidecarMissing() {
        let url = touchFile("clip.mov")
        XCTAssertNil(WorkspaceCacheService.loadIfFresh(for: url.path))
    }

    // MARK: - Schema versioning (C32 G2)

    /// A sidecar whose `version` is greater than
    /// `WorkspaceCacheService.currentVersion` must be rejected. The
    /// reader's guard exists so a future v2 sidecar dropped by a
    /// newer PurpleReel build doesn't get half-decoded by an older
    /// build that doesn't understand the new shape.
    func testLoadReturnsNilWhenVersionExceedsCurrent() throws {
        UserDefaults.standard.set(true, forKey: defaultsKey)
        let url = touchFile("clip.mov")
        // Write a payload manually with a higher version number.
        let attrs = (try? FileManager.default.attributesOfItem(
            atPath: url.path)) ?? [:]
        let mod = (attrs[.modificationDate] as? Date) ?? Date()
        let json = """
        {
          "version": 99,
          "filename": "clip.mov",
          "sizeBytes": 0,
          "modifiedAt": "\(ISO8601DateFormatter().string(from: mod))",
          "tech": {},
          "user": { "tags": [] },
          "markers": [],
          "subclips": []
        }
        """
        let sidecar = WorkspaceCacheService.sidecarURL(for: url.path)
        try FileManager.default.createDirectory(
            at: sidecar.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try json.write(to: sidecar, atomically: true, encoding: .utf8)
        XCTAssertNil(WorkspaceCacheService.loadIfFresh(for: url.path),
            "Sidecar with version > currentVersion must be refused")
    }

    /// Verify the `currentVersion` constant is the value the
    /// CHANGELOG / docs promise. Pinning it here prevents an
    /// accidental bump from sneaking past review — a real schema
    /// migration must update this number AND ship a migration
    /// path for existing sidecars (the latter isn't shipped yet,
    /// see C32 follow-up notes).
    func testCurrentVersionIsLockedAtOne() {
        XCTAssertEqual(WorkspaceCacheService.currentVersion, 1)
    }

    // MARK: - Multi-root workspace coverage (C32 G4)

    /// Two assets on different workspace roots each get their own
    /// sidecar under the *local* `.purplereel/` directory. Verifies
    /// the path math is per-asset (no global cache index that would
    /// collide across volumes).
    func testTwoRootsEachWriteToOwnPurplereelDirectory() throws {
        UserDefaults.standard.set(true, forKey: defaultsKey)
        let rootA = tempRoot.appendingPathComponent("RootA")
        let rootB = tempRoot.appendingPathComponent("RootB")
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
        let aURL = rootA.appendingPathComponent("a.mov")
        let bURL = rootB.appendingPathComponent("b.mov")
        FileManager.default.createFile(atPath: aURL.path, contents: Data())
        FileManager.default.createFile(atPath: bURL.path, contents: Data())
        WorkspaceCacheService.writePayload(samplePayload(for: aURL),
                                            for: aURL.path)
        WorkspaceCacheService.writePayload(samplePayload(for: bURL),
                                            for: bURL.path)
        let aSidecar = rootA.appendingPathComponent(".purplereel/a.mov.json")
        let bSidecar = rootB.appendingPathComponent(".purplereel/b.mov.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: aSidecar.path),
            "RootA sidecar must land in RootA/.purplereel")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bSidecar.path),
            "RootB sidecar must land in RootB/.purplereel")
        // Verify no cross-leakage — each loads back independently.
        XCTAssertNotNil(WorkspaceCacheService.loadIfFresh(for: aURL.path))
        XCTAssertNotNil(WorkspaceCacheService.loadIfFresh(for: bURL.path))
    }

    // MARK: - Orphan prune (C32 G1)

    func testPruneDeletesSidecarsWhoseSourceIsGone() throws {
        UserDefaults.standard.set(true, forKey: defaultsKey)
        let liveURL = touchFile("alive.mov")
        let goneURL = touchFile("doomed.mov")
        WorkspaceCacheService.writePayload(samplePayload(for: liveURL),
                                            for: liveURL.path)
        WorkspaceCacheService.writePayload(samplePayload(for: goneURL),
                                            for: goneURL.path)
        // Delete the source file but leave its sidecar.
        try FileManager.default.removeItem(at: goneURL)
        let result = WorkspaceCacheService.pruneOrphans(under: tempRoot)
        XCTAssertEqual(result.scanned, 2,
            "Both sidecars should be visited by the walker")
        XCTAssertEqual(result.deleted.count, 1,
            "Only the orphaned sidecar should be deleted")
        // The live sidecar must still exist.
        let aliveSidecar = WorkspaceCacheService.sidecarURL(for: liveURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: aliveSidecar.path),
            "Live sidecar must survive prune")
        // The orphan sidecar must be gone.
        let orphanSidecar = WorkspaceCacheService.sidecarURL(for: goneURL.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanSidecar.path),
            "Orphan sidecar must be deleted")
    }

    func testPruneOnEmptyTreeReturnsZeroes() {
        let result = WorkspaceCacheService.pruneOrphans(under: tempRoot)
        XCTAssertEqual(result, WorkspaceCacheService.PruneResult(
            scanned: 0, deleted: [], failed: []
        ))
    }

    // MARK: - Age-based eviction (C35 G3)

    /// `maxAgeDays = nil` (the default) is orphan-only, same as
    /// pre-C35 — a sidecar whose source file still exists must
    /// survive the prune regardless of how old it is.
    func testPruneWithoutAgeCapKeepsOldButLiveSidecars() throws {
        UserDefaults.standard.set(true, forKey: defaultsKey)
        let liveURL = touchFile("alive.mov")
        WorkspaceCacheService.writePayload(samplePayload(for: liveURL),
                                            for: liveURL.path)
        // Backdate the sidecar's mtime by 100 days.
        let sidecar = WorkspaceCacheService.sidecarURL(for: liveURL.path)
        let ancient = Date().addingTimeInterval(-100 * 86400)
        try FileManager.default.setAttributes(
            [.modificationDate: ancient], ofItemAtPath: sidecar.path
        )
        let result = WorkspaceCacheService.pruneOrphans(under: tempRoot)
        XCTAssertEqual(result.deleted.count, 0,
            "Live sidecar must survive when maxAgeDays is nil")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path))
    }

    /// With `maxAgeDays = 30`, a 100-day-old sidecar with a live
    /// source is deleted (age cap fires) while a fresh sidecar
    /// stays.
    func testPruneWithAgeCapDeletesOverAgeSidecars() throws {
        UserDefaults.standard.set(true, forKey: defaultsKey)
        let ancientURL = touchFile("ancient.mov")
        let freshURL = touchFile("fresh.mov")
        WorkspaceCacheService.writePayload(samplePayload(for: ancientURL),
                                            for: ancientURL.path)
        WorkspaceCacheService.writePayload(samplePayload(for: freshURL),
                                            for: freshURL.path)
        // Backdate just the "ancient" sidecar.
        let ancientSidecar = WorkspaceCacheService.sidecarURL(for: ancientURL.path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-100 * 86400)],
            ofItemAtPath: ancientSidecar.path
        )
        let result = WorkspaceCacheService.pruneOrphans(
            under: tempRoot, maxAgeDays: 30
        )
        XCTAssertEqual(result.deleted.count, 1,
            "Only the over-age sidecar should be deleted")
        let freshSidecar = WorkspaceCacheService.sidecarURL(for: freshURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshSidecar.path),
            "Fresh sidecar must survive the age-based prune")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ancientSidecar.path))
    }

    /// `maxAgeDays = 0` is treated as "disabled" — same behavior as
    /// nil. Mirrors the Settings stepper UX where 0 means "off".
    func testPruneWithZeroAgeCapIsOrphanOnly() throws {
        UserDefaults.standard.set(true, forKey: defaultsKey)
        let liveURL = touchFile("alive.mov")
        WorkspaceCacheService.writePayload(samplePayload(for: liveURL),
                                            for: liveURL.path)
        let sidecar = WorkspaceCacheService.sidecarURL(for: liveURL.path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-365 * 86400)],
            ofItemAtPath: sidecar.path
        )
        let result = WorkspaceCacheService.pruneOrphans(
            under: tempRoot, maxAgeDays: 0
        )
        XCTAssertEqual(result.deleted.count, 0,
            "maxAgeDays=0 must behave like nil (orphan-only)")
    }
}
