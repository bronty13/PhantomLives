import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PurpleDedupCore

/// Perceptual-hash tests use programmatically-generated images so the suite has no
/// binary fixtures and the patterns are reproducible across machines. Each helper draws
/// a deterministic gradient or checkerboard into a CGImage and writes it as PNG via
/// CGImageDestination.
final class PerceptualHasherTests: XCTestCase {

    func testIdenticalImagesProduceIdenticalHash() throws {
        let dir = try TestFixtures.makeTempDir("phash-identical")
        defer { TestFixtures.cleanup(dir) }

        let a = try writePNG(diagonalGradient(side: 256), at: dir.appendingPathComponent("a.png"))
        let b = try writePNG(diagonalGradient(side: 256), at: dir.appendingPathComponent("b.png"))

        let hasher = PerceptualHasher()
        let ha = try hasher.hash(imageAt: a)
        let hb = try hasher.hash(imageAt: b)

        XCTAssertEqual(ha.phash, hb.phash, "Bit-identical pixels must produce identical pHash")
        XCTAssertEqual(ha.dhash, hb.dhash, "Bit-identical pixels must produce identical dHash")
        XCTAssertEqual(PerceptualHash.hammingDistance(ha.phash, hb.phash), 0)
    }

    func testResizedImageStaysWithinThreshold() throws {
        // Same logical image rendered at 1.5× and 2× resolution — the kind of ratio
        // typical when a sharing app downsamples a phone photo. We assert the distance
        // is bounded by the "loosely similar" threshold (≤12). The "very similar" band
        // (≤6) is too tight for synthetic smooth gradients (anti-aliased resampling
        // perturbs DCT coefficients more than it does for real photos with structure).
        let dir = try TestFixtures.makeTempDir("phash-resized")
        defer { TestFixtures.cleanup(dir) }

        let small = try writePNG(diagonalGradient(side: 256), at: dir.appendingPathComponent("small.png"))
        let large = try writePNG(diagonalGradient(side: 384), at: dir.appendingPathComponent("large.png"))

        let hasher = PerceptualHasher()
        let hs = try hasher.hash(imageAt: small)
        let hl = try hasher.hash(imageAt: large)

        let dist = PerceptualHash.hammingDistance(hs.phash, hl.phash)
        XCTAssertLessThanOrEqual(dist, 12,
            "Resized copies should land in the 'loosely similar' band; got distance \(dist)")
    }

    func testStructurallyDifferentImagesAreDistant() throws {
        let dir = try TestFixtures.makeTempDir("phash-different")
        defer { TestFixtures.cleanup(dir) }

        // Two visually different patterns: a smooth gradient vs a checkerboard. Their
        // pHashes should differ in many bits.
        let g = try writePNG(diagonalGradient(side: 256), at: dir.appendingPathComponent("gradient.png"))
        let c = try writePNG(checkerboard(side: 256, blockSize: 16), at: dir.appendingPathComponent("checker.png"))

        let hasher = PerceptualHasher()
        let hg = try hasher.hash(imageAt: g)
        let hc = try hasher.hash(imageAt: c)

        let dist = PerceptualHash.hammingDistance(hg.phash, hc.phash)
        XCTAssertGreaterThan(dist, 12,
            "Structurally different patterns must be outside the 'loosely similar' band; got \(dist)")
    }

    func testWidthHeightCapturedFromOriginal() throws {
        let dir = try TestFixtures.makeTempDir("phash-dims")
        defer { TestFixtures.cleanup(dir) }

        let img = try writePNG(diagonalGradient(side: 384), at: dir.appendingPathComponent("img.png"))
        let h = try PerceptualHasher().hash(imageAt: img)
        XCTAssertEqual(h.width, 384)
        XCTAssertEqual(h.height, 384)
    }

    func testDecodeFailureSurfacesAsError() throws {
        let dir = try TestFixtures.makeTempDir("phash-corrupt")
        defer { TestFixtures.cleanup(dir) }

        let bad = try TestFixtures.write("not an image", to: dir.appendingPathComponent("nope.png"))
        XCTAssertThrowsError(try PerceptualHasher().hash(imageAt: bad))
    }

    // MARK: - synthetic image helpers

    /// Smooth diagonal gradient. Identical inputs → byte-identical output.
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

    /// Black-and-white checker. Visually distinct from the gradient; produces a high-
    /// frequency DCT signature that should land far from any smooth image.
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

    private func writePNG(_ image: CGImage, at url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw NSError(domain: "PerceptualHasherTests", code: 1)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "PerceptualHasherTests", code: 2)
        }
        return url
    }
}
