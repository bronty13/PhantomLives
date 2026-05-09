import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PurpleDedupCore

final class CachedScanEngineTests: XCTestCase {

    func testFirstRunMissesCacheSecondRunHits() async throws {
        let dir = try TestFixtures.makeTempDir("cache-hits")
        defer { TestFixtures.cleanup(dir) }

        // Two byte-identical photos so the exact stage actually does work.
        let bytes = Data(repeating: 0xAB, count: 4096)
        try TestFixtures.write(bytes, to: dir.appendingPathComponent("a.jpg"))
        try TestFixtures.write(bytes, to: dir.appendingPathComponent("b.jpg"))

        let db = try Database.inMemory()
        let engine = CachedScanEngine(database: db)

        let firstRun = try await engine.scan(
            sources: [ScanSource(url: dir)],
            options: ScanOptions(kinds: [.photo]),
            perceptual: ScanEngine.PerceptualOptions(enabled: false),
            video: ScanEngine.VideoOptions(enabled: false)
        )
        XCTAssertEqual(firstRun.cache.contentHashHits, 0, "Cold cache → zero hits")
        XCTAssertEqual(firstRun.cache.contentHashMisses, 2)
        XCTAssertEqual(firstRun.result.exactClusters.count, 1)

        // Second run: same files, unchanged → 100% cache hit.
        let secondRun = try await engine.scan(
            sources: [ScanSource(url: dir)],
            options: ScanOptions(kinds: [.photo]),
            perceptual: ScanEngine.PerceptualOptions(enabled: false),
            video: ScanEngine.VideoOptions(enabled: false)
        )
        XCTAssertEqual(secondRun.cache.contentHashHits, 2,
            "Warm cache → all candidates hit")
        XCTAssertEqual(secondRun.cache.contentHashMisses, 0)
        XCTAssertEqual(secondRun.result.exactClusters.count, 1,
            "Cache hit must produce the same cluster as a fresh hash")
    }

    func testMtimeChangeInvalidatesCache() async throws {
        let dir = try TestFixtures.makeTempDir("cache-mtime")
        defer { TestFixtures.cleanup(dir) }

        let a = try TestFixtures.write(Data(repeating: 0x01, count: 1024), to: dir.appendingPathComponent("a.jpg"))
        let b = try TestFixtures.write(Data(repeating: 0x01, count: 1024), to: dir.appendingPathComponent("b.jpg"))

        let db = try Database.inMemory()
        let engine = CachedScanEngine(database: db)

        _ = try await engine.scan(
            sources: [ScanSource(url: dir)],
            options: ScanOptions(kinds: [.photo]),
            perceptual: ScanEngine.PerceptualOptions(enabled: false),
            video: ScanEngine.VideoOptions(enabled: false)
        )

        // Mutate "a" — same content, but mtime moves forward. Cache must miss it.
        try Data(repeating: 0x01, count: 1024).write(to: a, options: .atomic)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)],
            ofItemAtPath: a.path
        )
        // Don't touch "b" — its row should still be valid.
        _ = b

        let secondRun = try await engine.scan(
            sources: [ScanSource(url: dir)],
            options: ScanOptions(kinds: [.photo]),
            perceptual: ScanEngine.PerceptualOptions(enabled: false),
            video: ScanEngine.VideoOptions(enabled: false)
        )
        XCTAssertEqual(secondRun.cache.contentHashMisses, 1, "Only the touched file should miss")
        XCTAssertEqual(secondRun.cache.contentHashHits, 1, "The untouched file should hit")
    }

    func testPerceptualCacheRoundTrip() async throws {
        let dir = try TestFixtures.makeTempDir("cache-perc")
        defer { TestFixtures.cleanup(dir) }

        let a = dir.appendingPathComponent("a.png")
        let b = dir.appendingPathComponent("b.png")
        try writePNG(diagonalGradient(side: 256), at: a)
        try writePNG(diagonalGradient(side: 384), at: b)

        let db = try Database.inMemory()
        let engine = CachedScanEngine(database: db)

        let first = try await engine.scan(
            sources: [ScanSource(url: dir)],
            options: ScanOptions(kinds: [.photo]),
            perceptual: ScanEngine.PerceptualOptions(enabled: true, threshold: 12),
            video: ScanEngine.VideoOptions(enabled: false)
        )
        XCTAssertEqual(first.cache.perceptualMisses, 2, "Cold cache → both miss")
        XCTAssertEqual(first.cache.perceptualHits, 0)
        XCTAssertEqual(first.result.similarClusters.count, 1)

        // Scan again at a *different* threshold. No I/O or hashing should happen for
        // the perceptual stage — just re-clustering from cached fingerprints.
        let second = try await engine.scan(
            sources: [ScanSource(url: dir)],
            options: ScanOptions(kinds: [.photo]),
            perceptual: ScanEngine.PerceptualOptions(enabled: true, threshold: 24),
            video: ScanEngine.VideoOptions(enabled: false)
        )
        XCTAssertEqual(second.cache.perceptualHits, 2, "Warm cache → both hit, regardless of threshold")
        XCTAssertEqual(second.cache.perceptualMisses, 0)
        XCTAssertEqual(second.result.similarClusters.count, 1)
    }

    // MARK: - helpers

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

    @discardableResult
    private func writePNG(_ image: CGImage, at url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw NSError(domain: "CachedScanEngineTests", code: 1) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "CachedScanEngineTests", code: 2)
        }
        return url
    }

    // MARK: - Photos lookup mode

    /// Lookup-mode source's content hashes go into the lookup index. They
    /// don't form clusters, don't show up in `filesScanned`, and DO appear
    /// in `photosLookupHashes` so the GUI can render the badge.
    func testLookupOnlySourceContributesHashesButNoClusters() async throws {
        let scanDir = try TestFixtures.makeTempDir("lookup-scan")
        let lookupDir = try TestFixtures.makeTempDir("lookup-ref")
        defer { TestFixtures.cleanup(scanDir); TestFixtures.cleanup(lookupDir) }

        let bytes = Data(repeating: 0x77, count: 4096)
        try TestFixtures.write(bytes, to: scanDir.appendingPathComponent("a.jpg"))
        try TestFixtures.write(bytes, to: scanDir.appendingPathComponent("b.jpg"))
        try TestFixtures.write(bytes, to: lookupDir.appendingPathComponent("ref.jpg"))

        let uniqueBytes = Data(repeating: 0x99, count: 2048)
        try TestFixtures.write(uniqueBytes, to: lookupDir.appendingPathComponent("only-in-lookup.jpg"))

        let db = try Database.inMemory()
        let engine = CachedScanEngine(database: db)

        let pair = try await engine.scan(
            sources: [
                ScanSource(url: scanDir),
                ScanSource(url: lookupDir, isLocked: true, isLookupOnly: true),
            ],
            options: ScanOptions(kinds: [.photo]),
            perceptual: ScanEngine.PerceptualOptions(enabled: false),
            video: ScanEngine.VideoOptions(enabled: false)
        )

        XCTAssertEqual(pair.result.exactClusters.count, 1,
                       "Lookup source must not interfere with regular clustering")
        XCTAssertEqual(pair.result.filesScanned, 2,
                       "Lookup source files must NOT count toward filesScanned")
        XCTAssertEqual(pair.result.photosLookupCount, 2,
                       "Lookup index must include both files in the lookup source")

        let sharedHash = pair.result.exactClusters.first?.contentHashHex
        XCTAssertNotNil(sharedHash)
        XCTAssertTrue(pair.result.photosLookupHashes.contains(sharedHash!),
                      "Shared content hash must be present in the lookup index")
    }

    func testOnlyLookupSourceProducesEmptyClustersAndPopulatedIndex() async throws {
        let lookupDir = try TestFixtures.makeTempDir("lookup-only")
        defer { TestFixtures.cleanup(lookupDir) }

        try TestFixtures.write(Data(repeating: 0x55, count: 1024),
                               to: lookupDir.appendingPathComponent("x.jpg"))
        try TestFixtures.write(Data(repeating: 0x66, count: 2048),
                               to: lookupDir.appendingPathComponent("y.jpg"))

        let db = try Database.inMemory()
        let engine = CachedScanEngine(database: db)

        let pair = try await engine.scan(
            sources: [ScanSource(url: lookupDir, isLocked: true, isLookupOnly: true)],
            options: ScanOptions(kinds: [.photo]),
            perceptual: ScanEngine.PerceptualOptions(enabled: false),
            video: ScanEngine.VideoOptions(enabled: false)
        )

        XCTAssertEqual(pair.result.exactClusters.count, 0)
        XCTAssertEqual(pair.result.filesScanned, 0)
        XCTAssertEqual(pair.result.photosLookupCount, 2)
        XCTAssertEqual(pair.result.photosLookupHashes.count, 2)
    }
}
