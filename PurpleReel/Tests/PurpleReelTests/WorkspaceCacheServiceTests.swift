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
}
