import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PurpleDedupCore

final class MetadataExtractorTests: XCTestCase {

    func testReturnsDimensionsForGeneratedPNG() async throws {
        let dir = try TestFixtures.makeTempDir("meta-png")
        defer { TestFixtures.cleanup(dir) }

        let url = dir.appendingPathComponent("a.png")
        try writePNG(makeImage(width: 320, height: 240), at: url)

        let m = await MetadataExtractor().extract(url: url)
        XCTAssertEqual(m.pixelWidth, 320)
        XCTAssertEqual(m.pixelHeight, 240)
    }

    func testReturnsEmptyMetadataForUnsupportedFile() async throws {
        let dir = try TestFixtures.makeTempDir("meta-bad")
        defer { TestFixtures.cleanup(dir) }
        let url = try TestFixtures.write("not an image", to: dir.appendingPathComponent("readme.txt"))
        let m = await MetadataExtractor().extract(url: url)
        // .txt isn't a recognised photo or video extension — extractor returns
        // empty metadata rather than throwing.
        XCTAssertNil(m.pixelWidth)
        XCTAssertNil(m.captureDate)
        XCTAssertNil(m.codec)
    }

    func testRowsIncludeOnlyPopulatedFields() {
        var m = FileMetadata()
        m.pixelWidth = 1920
        m.pixelHeight = 1080
        m.iso = 100
        let labels = m.rows().map(\.label)
        XCTAssertTrue(labels.contains("Dimensions"))
        XCTAssertTrue(labels.contains("ISO"))
        XCTAssertFalse(labels.contains("Camera"))   // never set
        XCTAssertFalse(labels.contains("Aperture")) // never set
    }

    func testApertureFormatsAsFNumber() {
        var m = FileMetadata()
        m.aperture = 1.8
        let row = m.rows().first { $0.id == "aperture" }
        XCTAssertEqual(row?.value, "ƒ/1.8")
    }

    func testShutterFormatsFastExposureAsFraction() {
        // Verified by extractor when it sees a sub-second exposureTime; here we
        // just confirm the row formatting works for the populated value.
        var m = FileMetadata()
        m.shutterSpeed = "1/250 s"
        let row = m.rows().first { $0.id == "shutter" }
        XCTAssertEqual(row?.value, "1/250 s")
    }

    // MARK: - helpers

    private func makeImage(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 4 * width,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.3, blue: 0.7, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
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
        ) else { throw NSError(domain: "MetadataExtractorTests", code: 1) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "MetadataExtractorTests", code: 2)
        }
        return url
    }
}
