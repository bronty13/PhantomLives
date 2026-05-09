import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PurpleDedupCore

final class RotatedClustererTests: XCTestCase {

    // MARK: - rotation buffer math

    func testRotate90Clockwise() {
        // 3×3 buffer for a hand-checkable test.
        //
        //   1 2 3        7 4 1
        //   4 5 6  -->   8 5 2
        //   7 8 9        9 6 3
        let src: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
        let rotated = PerceptualHasher.rotate90Clockwise(src, side: 3)
        XCTAssertEqual(rotated, [7, 4, 1, 8, 5, 2, 9, 6, 3])
    }

    func testRotate180EqualsReversed() {
        let src: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
        let rotated = PerceptualHasher.rotate180(src, side: 3)
        XCTAssertEqual(rotated, [9, 8, 7, 6, 5, 4, 3, 2, 1])
    }

    func testFourSuccessive90sReturnToIdentity() {
        // Property: rotating four times = identity. 32×32 to match the actual
        // pHash buffer size.
        var buf = [UInt8](repeating: 0, count: 32 * 32)
        for i in 0..<buf.count { buf[i] = UInt8(i & 0xFF) }
        var rotated = buf
        for _ in 0..<4 { rotated = PerceptualHasher.rotate90Clockwise(rotated, side: 32) }
        XCTAssertEqual(rotated, buf)
    }

    // MARK: - clusterer

    func testIdenticalRotationHashesCluster() {
        // Two files whose rotation arrays are identical bit-for-bit — must
        // cluster as rotation duplicates regardless of the threshold.
        let h: [UInt64] = [0xAAAA_BBBB, 0xCCCC_DDDD, 0xEEEE_FFFF, 0x1111_2222]
        let entries = [makeEntry(path: "/a.jpg", hashes: h), makeEntry(path: "/b.jpg", hashes: h)]
        let clusters = RotatedClusterer().clusterRotated(entries: entries)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.first?.files.count, 2)
    }

    func testRotation90DetectedAcrossPair() {
        // One file's hash[0] equals the other's hash[1] (90°). They should
        // cluster, and the rotation-relative-to-first should be 90°.
        let aHashes: [UInt64] = [0x1, 0x2, 0x3, 0x4]
        let bHashes: [UInt64] = [0x5, 0x1, 0x6, 0x7]   // hash[1] matches a.hash[0] exactly
        let entries = [
            makeEntry(path: "/a.jpg", hashes: aHashes),
            makeEntry(path: "/b.jpg", hashes: bHashes),
        ]
        let clusters = RotatedClusterer().clusterRotated(entries: entries, threshold: 0)
        XCTAssertEqual(clusters.count, 1)
        let cluster = clusters.first!
        XCTAssertEqual(cluster.files.count, 2)
        // Rotations are listed in alphabetical-path order; index 0 is /a.jpg
        // (rotation 0 by definition), index 1 is /b.jpg (rotation = the k where
        // b.hashes[k] best matches a.hashes[0]).
        XCTAssertEqual(cluster.rotationsRelativeToFirst[0], 0)
        XCTAssertEqual(cluster.rotationsRelativeToFirst[1], 90)
    }

    func testCompletelyDifferentHashesDoNotCluster() {
        let a: [UInt64] = [0x0000_0000, 0x0000_0000, 0x0000_0000, 0x0000_0000]
        let b: [UInt64] = [0xFFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFF,
                           0xFFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFF]
        let entries = [makeEntry(path: "/a.jpg", hashes: a), makeEntry(path: "/b.jpg", hashes: b)]
        XCTAssertTrue(RotatedClusterer().clusterRotated(entries: entries).isEmpty)
    }

    func testExclusionByURL() {
        let h: [UInt64] = [0x1, 0x2, 0x3, 0x4]
        let entries = [
            makeEntry(path: "/a.jpg", hashes: h),
            makeEntry(path: "/b.jpg", hashes: h),
        ]
        let clusters = RotatedClusterer().clusterRotated(
            entries: entries, excluding: [URL(fileURLWithPath: "/a.jpg")]
        )
        XCTAssertTrue(clusters.isEmpty)
    }

    // MARK: - end-to-end with a real (programmatically-generated) rotated PNG

    func testRealImagePairWithKnown90DegreeRotation() throws {
        let dir = try TestFixtures.makeTempDir("rot-real")
        defer { TestFixtures.cleanup(dir) }

        let upright = makeAsymmetricGradient(side: 256, rotation: 0)
        let sideways = makeAsymmetricGradient(side: 256, rotation: 90)
        let upURL = try writePNG(upright, at: dir.appendingPathComponent("up.png"))
        let sideURL = try writePNG(sideways, at: dir.appendingPathComponent("side.png"))

        let hasher = PerceptualHasher()
        let upHashes = try hasher.hashWithRotations(imageAt: upURL)
        let sideHashes = try hasher.hashWithRotations(imageAt: sideURL)

        // The cross-rotation match should land within the default threshold
        // even though the regular 0°-vs-0° comparison wouldn't (the images
        // are deliberately asymmetric so 0°-vs-90° has high Hamming distance).
        let clusterer = RotatedClusterer()
        let dist = clusterer.rotationDistance(upHashes, sideHashes)
        XCTAssertLessThanOrEqual(dist, RotatedClusterer.defaultThreshold + 4,
            "Cross-rotation distance \(dist) should be small for known-rotated copies")
    }

    // MARK: - helpers

    private func makeEntry(path: String, hashes: [UInt64]) -> RotatedClusterer.Entry {
        let f = DiscoveredFile(
            url: URL(fileURLWithPath: path),
            sizeBytes: 100,
            modificationTime: Date(),
            isLocked: false
        )
        return RotatedClusterer.Entry(file: f, rotationHashes: hashes)
    }

    /// An asymmetric grayscale gradient that's visibly different at each
    /// rotation. The pHash of the 0° version differs significantly from
    /// the pHash of the 90° version, but `RotatedClusterer.rotationDistance`
    /// matches them via the cross-rotation slot.
    private func makeAsymmetricGradient(side: Int, rotation: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(
            data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side,
            space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        let buf = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<side {
            for x in 0..<side {
                // Asymmetric: light bias toward the left edge + a sun-like
                // bright disc in the upper-left quadrant. Different at each
                // rotation.
                let leftBias = 200 - (x * 200 / side)
                let dx = x - side / 4, dy = y - side / 4
                let radius = Int(Double(dx * dx + dy * dy).squareRoot())
                let sun = max(0, 60 - radius)
                buf[y * side + x] = UInt8(min(255, max(0, leftBias + sun)))
            }
        }
        let img = ctx.makeImage()!
        if rotation == 0 { return img }
        // Apply the requested rotation by drawing into a new context with
        // the appropriate transform. CG rotates around the origin so we
        // translate to centre, rotate, translate back.
        let rotatedCtx = CGContext(
            data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side,
            space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        rotatedCtx.translateBy(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
        rotatedCtx.rotate(by: -CGFloat(rotation) * .pi / 180)
        rotatedCtx.translateBy(x: -CGFloat(side) / 2, y: -CGFloat(side) / 2)
        rotatedCtx.draw(img, in: CGRect(x: 0, y: 0, width: side, height: side))
        return rotatedCtx.makeImage()!
    }

    @discardableResult
    private func writePNG(_ image: CGImage, at url: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw NSError(domain: "RotatedClustererTests", code: 1) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "RotatedClustererTests", code: 2)
        }
        return url
    }
}
