import XCTest
import AppKit
import PDFKit
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
        let pdf = try write("doc.pdf", Array("%PDF-1.4".utf8))
        let bin = try write("data.bin", [0x00, 0x01, 0x02])

        XCTAssertEqual(FileImportService.classify(png), .image)
        XCTAssertEqual(FileImportService.classify(mov), .video)
        XCTAssertEqual(FileImportService.classify(m4a), .audio)
        XCTAssertEqual(FileImportService.classify(mp3), .audio)
        XCTAssertEqual(FileImportService.classify(pdf), .pdf)
        XCTAssertEqual(FileImportService.classify(bin), .file)   // anything else → generic file
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

    func testMakeGenericFileAttachmentStoresBytesVerbatim() async throws {
        let bytes: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBE, 0x00, 0x11]
        let bin = try write("ticket.bin", bytes)
        let made = await FileImportService.makeAttachment(from: bin, entryId: "E1")
        let a = try XCTUnwrap(made)
        XCTAssertEqual(a.kind, "file")
        XCTAssertTrue(a.isFile)
        XCTAssertEqual(a.filename, "ticket.bin")
        XCTAssertEqual(a.data, Data(bytes), "generic files are stored byte-for-byte")
        XCTAssertNil(a.thumbnailData)
    }

    func testMakePDFAttachmentWithThumbnailAndPageCount() async throws {
        // Build a one-page PDF from an image so PDFKit can render a thumbnail.
        let page = PDFPage(image: NSImage(data: solidPNG(width: 200, height: 260))!)!
        let doc = PDFDocument(); doc.insert(page, at: 0)
        let pdfURL = scratch.appendingPathComponent("receipt.pdf")
        try XCTUnwrap(doc.dataRepresentation()).write(to: pdfURL)

        let made = await FileImportService.makeAttachment(from: pdfURL, entryId: "E1")
        let a = try XCTUnwrap(made)
        XCTAssertEqual(a.kind, "pdf")
        XCTAssertTrue(a.isPDF)
        XCTAssertEqual(a.mimeType, "application/pdf")
        XCTAssertEqual(a.height, 1, "page count stored in height (display-only)")
        XCTAssertNotNil(a.thumbnailData, "PDF first-page thumbnail")
    }

    func testUnreadablePathYieldsNil() async throws {
        let missing = scratch.appendingPathComponent("does-not-exist.bin")
        let result = await FileImportService.makeAttachment(from: missing, entryId: "E1")
        XCTAssertNil(result)
    }
}
