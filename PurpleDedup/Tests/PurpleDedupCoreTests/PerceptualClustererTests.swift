import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PurpleDedupCore

/// End-to-end tests for the perceptual stage: images on disk → ScanEngine → clusters.
final class PerceptualClustererTests: XCTestCase {

    func testGroupsResizedCopiesIntoSingleCluster() async throws {
        let dir = try TestFixtures.makeTempDir("perc-cluster")
        defer { TestFixtures.cleanup(dir) }

        // Same logical pattern at three sizes — should cluster together.
        try writePNG(diagonalGradient(side: 128), at: dir.appendingPathComponent("a_small.png"))
        try writePNG(diagonalGradient(side: 256), at: dir.appendingPathComponent("a_med.png"))
        try writePNG(diagonalGradient(side: 384), at: dir.appendingPathComponent("a_large.png"))
        // Decoy: visually distinct pattern → must not enter the cluster above.
        try writePNG(checkerboard(side: 256, blockSize: 16), at: dir.appendingPathComponent("decoy.png"))

        let result = try await ScanEngine().scan(
            sources: [ScanSource(url: dir)],
            options: ScanOptions(kinds: [.photo]),
            perceptual: ScanEngine.PerceptualOptions(enabled: true, threshold: 6)
        )

        XCTAssertEqual(result.exactClusters.count, 0,
            "Different file bytes (different sizes) must not exact-cluster")
        XCTAssertEqual(result.similarClusters.count, 1, "Three resized copies should form one similar cluster")
        XCTAssertEqual(result.similarClusters.first?.files.count, 3)
    }

    func testExactDupesNotDoubleReportedAsSimilar() async throws {
        let dir = try TestFixtures.makeTempDir("perc-noov")
        defer { TestFixtures.cleanup(dir) }

        // Two byte-identical copies → exact cluster. The perceptual stage must skip them
        // (it would otherwise group them again, plus any near-similar files, polluting
        // the "similar" listing with already-known dupes).
        let img = diagonalGradient(side: 256)
        try writePNG(img, at: dir.appendingPathComponent("copy1.png"))
        try writePNG(img, at: dir.appendingPathComponent("copy2.png"))

        let result = try await ScanEngine().scan(
            sources: [ScanSource(url: dir)],
            options: ScanOptions(kinds: [.photo]),
            perceptual: ScanEngine.PerceptualOptions(enabled: true, threshold: 6)
        )
        XCTAssertEqual(result.exactClusters.count, 1)
        XCTAssertEqual(result.similarClusters.count, 0,
            "Files already in an exact cluster must be excluded from the similar pass")
    }

    func testPerceptualOptionsDisabled() async throws {
        let dir = try TestFixtures.makeTempDir("perc-off")
        defer { TestFixtures.cleanup(dir) }

        try writePNG(diagonalGradient(side: 128), at: dir.appendingPathComponent("a.png"))
        try writePNG(diagonalGradient(side: 256), at: dir.appendingPathComponent("b.png"))

        let result = try await ScanEngine().scan(
            sources: [ScanSource(url: dir)],
            options: ScanOptions(kinds: [.photo]),
            perceptual: ScanEngine.PerceptualOptions(enabled: false, threshold: 6)
        )
        XCTAssertEqual(result.similarClusters.count, 0,
            "PerceptualOptions(enabled: false) must skip the similar pass entirely")
    }

    /// OR-of-distances: photos whose pHash distance is *above* the threshold should
    /// still cluster together when their dHash distance is *under* it. Built by
    /// constructing PerceptualHashes directly so we can pin the bit pattern.
    func testORofDistances_dHashAloneMergesCluster() {
        let nowURL = URL(fileURLWithPath: "/tmp/x")
        func file(_ name: String) -> DiscoveredFile {
            DiscoveredFile(
                url: nowURL.appendingPathComponent(name),
                sizeBytes: 1024,
                modificationTime: Date(timeIntervalSince1970: 0),
                isLocked: false
            )
        }
        // Two photos: dHash differs in 2 bits, pHash differs in 30 bits.
        // Threshold = 6 → pHash alone would NOT merge; dHash alone DOES.
        let a = PerceptualHash(phash: 0x0000_0000_0000_0000,
                               dhash: 0xAAAA_AAAA_AAAA_AAAA, width: 1, height: 1)
        let b = PerceptualHash(phash: 0xFFFF_FFFF_C000_0000,  // ~30 bits set
                               dhash: 0xAAAA_AAAA_AAAA_AAA8, // 2 bits flipped
                               width: 1, height: 1)
        XCTAssertGreaterThan(PerceptualHash.hammingDistance(a.phash, b.phash), 6)
        XCTAssertLessThanOrEqual(PerceptualHash.hammingDistance(a.dhash, b.dhash), 6)

        let clusters = PerceptualClusterer().clusterSimilar(
            entries: [(file("a.png"), a), (file("b.png"), b)],
            threshold: 6
        )
        XCTAssertEqual(clusters.count, 1, "OR-of-distances should merge a/b via dHash")
        XCTAssertEqual(clusters.first?.files.count, 2)
        // Diameter is min(pHash diameter, dHash diameter) — should be the small one.
        XCTAssertLessThanOrEqual(clusters.first?.maxPairwiseDistance ?? 999, 6)
    }

    /// Sanity check: when both hashes differ widely, the photos must NOT cluster.
    func testORofDistances_independentNoiseDoesNotCluster() {
        let nowURL = URL(fileURLWithPath: "/tmp/x")
        func file(_ name: String) -> DiscoveredFile {
            DiscoveredFile(
                url: nowURL.appendingPathComponent(name),
                sizeBytes: 1024,
                modificationTime: Date(timeIntervalSince1970: 0),
                isLocked: false
            )
        }
        let a = PerceptualHash(phash: 0x0000_0000_0000_0000,
                               dhash: 0x0000_0000_0000_0000,
                               width: 1, height: 1)
        let b = PerceptualHash(phash: 0xFFFF_FFFF_FFFF_FFFF,
                               dhash: 0xFFFF_FFFF_FFFF_FFFF,
                               width: 1, height: 1)
        XCTAssertEqual(PerceptualHash.hammingDistance(a.phash, b.phash), 64)
        XCTAssertEqual(PerceptualHash.hammingDistance(a.dhash, b.dhash), 64)

        let clusters = PerceptualClusterer().clusterSimilar(
            entries: [(file("a.png"), a), (file("b.png"), b)],
            threshold: 6
        )
        XCTAssertEqual(clusters.count, 0)
    }

    func testReportSerializesSimilarClusters() async throws {
        let dir = try TestFixtures.makeTempDir("perc-report")
        defer { TestFixtures.cleanup(dir) }

        try writePNG(diagonalGradient(side: 128), at: dir.appendingPathComponent("a.png"))
        try writePNG(diagonalGradient(side: 256), at: dir.appendingPathComponent("b.png"))

        let result = try await ScanEngine().scan(
            sources: [ScanSource(url: dir)],
            options: ScanOptions(kinds: [.photo]),
            perceptual: ScanEngine.PerceptualOptions(enabled: true, threshold: 6)
        )
        let report = result.report()
        let json = try report.toJSONData(pretty: false)
        let decoded = try JSONDecoder().decode(ScanReport.self, from: json)

        XCTAssertEqual(decoded.similarClusterCount, 1)
        let similar = decoded.clusters.first { $0.kind == "similar_photo" }
        XCTAssertNotNil(similar)
        XCTAssertEqual(similar?.fileCount, 2)
        XCTAssertNotNil(similar?.maxPairwiseDistance)
        XCTAssertEqual(decoded.similarityThreshold, 6)
    }

    // MARK: - helpers (shared with PerceptualHasherTests; kept inline so each test file
    // can be read independently)

    private func diagonalGradient(side: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(
            data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side,
            space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        let buf = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<side {
            for x in 0..<side {
                let v = (x + y) * 255 / (2 * side - 1)
                buf[y * side + x] = UInt8(min(255, max(0, v)))
            }
        }
        return ctx.makeImage()!
    }

    private func checkerboard(side: Int, blockSize: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(
            data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side,
            space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        let buf = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<side {
            for x in 0..<side {
                let bx = x / blockSize
                let by = y / blockSize
                buf[y * side + x] = ((bx + by) % 2 == 0) ? 0 : 255
            }
        }
        return ctx.makeImage()!
    }

    @discardableResult
    private func writePNG(_ image: CGImage, at url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw NSError(domain: "PerceptualClustererTests", code: 1)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "PerceptualClustererTests", code: 2)
        }
        return url
    }
}
