import XCTest
import AppKit
@testable import PurpleDiary

/// Covers the filesystem import path: content-type classification and building
/// an image attachment from a file on disk. Video poster decoding needs a real
/// movie + AVFoundation, so it's verified by hand (like the live PhotoKit
/// import); the classification of video URLs is covered here.
@MainActor
final class FileImportTests: XCTestCase {

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("pd-fileimport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func write(_ name: String, _ bytes: [UInt8]) throws -> URL {
        let url = scratch.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    private func solidPNG(width: Int, height: Int) -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemPurple.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testClassifyByContentType() throws {
        let png = scratch.appendingPathComponent("pic.png")
        try solidPNG(width: 8, height: 8).write(to: png)
        let mov = try write("clip.mov", [0x00, 0x00, 0x00, 0x14])
        let m4a = try write("voice.m4a", [0x00, 0x00, 0x00, 0x18])
        let mp3 = try write("song.mp3", [0x49, 0x44, 0x33])
        let txt = try write("notes.txt", Array("hello".utf8))

        XCTAssertEqual(FileImportService.classify(png), .image)
        XCTAssertEqual(FileImportService.classify(mov), .video)
        XCTAssertEqual(FileImportService.classify(m4a), .audio)
        XCTAssertEqual(FileImportService.classify(mp3), .audio)
        XCTAssertEqual(FileImportService.classify(txt), .unsupported)
    }

    func testMakeImageAttachmentFromFile() async throws {
        let png = scratch.appendingPathComponent("big.png")
        try solidPNG(width: 4000, height: 3000).write(to: png)

        let made = await FileImportService.makeAttachment(from: png, entryId: "E1")
        let a = try XCTUnwrap(made)
        XCTAssertEqual(a.kind, "photo")
        XCTAssertEqual(a.mimeType, "image/jpeg")
        XCTAssertEqual(a.entryId, "E1")
        XCTAssertEqual(a.filename, "big.png")
        XCTAssertNil(a.sourceAssetId)
        // Re-encoded as a downscaled JPEG (longest edge clamped to maxImageEdge).
        XCTAssertEqual(Array(a.data.prefix(2)), [0xFF, 0xD8])
        XCTAssertEqual(max(a.width, a.height), Int(ImageProcessing.maxImageEdge))
        XCTAssertNotNil(a.thumbnailData)
    }

    func testMakeAudioAttachmentFromFile() async throws {
        // Audio bytes are stored verbatim — no decode required, so arbitrary
        // bytes with an audio extension exercise the full path.
        let bytes: [UInt8] = [0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]
        let m4a = try write("memo.m4a", bytes)

        let made = await FileImportService.makeAttachment(from: m4a, entryId: "E1")
        let a = try XCTUnwrap(made)
        XCTAssertEqual(a.kind, "audio")
        XCTAssertTrue(a.isAudio)
        XCTAssertTrue(a.mimeType.hasPrefix("audio/"))
        XCTAssertEqual(a.filename, "memo.m4a")
        XCTAssertEqual(a.data, Data(bytes), "audio is stored byte-for-byte")
        XCTAssertNil(a.thumbnailData, "audio has no visual thumbnail")
        XCTAssertEqual(a.width, 0)
        XCTAssertEqual(a.height, 0)
        XCTAssertNil(a.sourceAssetId)
    }

    func testUnsupportedFileYieldsNil() async throws {
        let txt = try write("doc.txt", Array("not media".utf8))
        let result = await FileImportService.makeAttachment(from: txt, entryId: "E1")
        XCTAssertNil(result)
    }
}
