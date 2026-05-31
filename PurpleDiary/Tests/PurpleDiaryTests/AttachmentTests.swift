import XCTest
import AppKit
@testable import PurpleDiary

/// Covers the attachment data layer (via the shared service, which routes to a
/// disposable temp DB under XCTest) and the pure ImageProcessing resizing.
/// PhotoKit itself can't run headlessly, so the live import is verified by hand.
@MainActor
final class AttachmentTests: XCTestCase {

    private func attachment(_ id: String, entry: String, asset: String?, bytes: [UInt8] = [0xFF, 0xD8, 0xFF]) -> Attachment {
        let data = Data(bytes)
        return Attachment(id: id, entryId: entry, kind: "photo",
                          filename: "\(id).jpg", mimeType: "image/jpeg",
                          sizeBytes: Int64(data.count), width: 2, height: 2,
                          data: data, thumbnailData: Data([0x01]),
                          sourceAssetId: asset, createdAt: DatabaseService.isoNow())
    }

    func testInsertFetchCountAndDedupe() throws {
        let entry = Entry.newDraft(title: "photos")
        try DatabaseService.shared.insertEntry(entry)

        try DatabaseService.shared.insertAttachment(attachment("A1", entry: entry.id, asset: "asset/1"))
        try DatabaseService.shared.insertAttachment(attachment("A2", entry: entry.id, asset: "asset/2"))

        let full = try DatabaseService.shared.attachments(forEntry: entry.id)
        XCTAssertEqual(full.count, 2)
        XCTAssertEqual(Set(full.map(\.id)), ["A1", "A2"])

        let thumbs = try DatabaseService.shared.attachmentThumbs(forEntry: entry.id)
        XCTAssertEqual(thumbs.count, 2)

        let counts = try DatabaseService.shared.attachmentCountByEntry()
        XCTAssertEqual(counts[entry.id], 2)

        XCTAssertTrue(try DatabaseService.shared.attachmentExists(entryId: entry.id, sourceAssetId: "asset/1"))
        XCTAssertFalse(try DatabaseService.shared.attachmentExists(entryId: entry.id, sourceAssetId: "asset/none"))

        try DatabaseService.shared.deleteAttachment(id: "A1")
        XCTAssertEqual(try DatabaseService.shared.attachments(forEntry: entry.id).count, 1)

        // Clean up so we don't leave rows in the (per-process temp) DB.
        try DatabaseService.shared.deleteEntry(id: entry.id)
    }

    /// The lightweight thumb projection must carry kind + mimeType so the strip
    /// can badge videos and the viewer can pick image-vs-player without the BLOB.
    func testThumbProjectionCarriesKindAndMimeType() throws {
        let entry = Entry.newDraft(title: "mixed media")
        try DatabaseService.shared.insertEntry(entry)
        defer { try? DatabaseService.shared.deleteEntry(id: entry.id) }

        try DatabaseService.shared.insertAttachment(attachment("P1", entry: entry.id, asset: nil))
        var vid = attachment("V1", entry: entry.id, asset: nil)
        vid.kind = "video"; vid.mimeType = "video/quicktime"; vid.filename = "V1.mov"
        try DatabaseService.shared.insertAttachment(vid)

        let thumbs = try DatabaseService.shared.attachmentThumbs(forEntry: entry.id)
        let byId = Dictionary(uniqueKeysWithValues: thumbs.map { ($0.id, $0) })
        XCTAssertEqual(byId["P1"]?.kind, "photo")
        XCTAssertEqual(byId["P1"]?.isVideo, false)
        XCTAssertEqual(byId["V1"]?.kind, "video")
        XCTAssertEqual(byId["V1"]?.mimeType, "video/quicktime")
        XCTAssertEqual(byId["V1"]?.isVideo, true)
    }

    /// The viewer fetches one full row (bytes included) by id.
    func testAttachmentByIdRoundTrips() throws {
        let entry = Entry.newDraft(title: "viewer")
        try DatabaseService.shared.insertEntry(entry)
        defer { try? DatabaseService.shared.deleteEntry(id: entry.id) }

        let a = attachment("X1", entry: entry.id, asset: nil, bytes: [0xFF, 0xD8, 0xFF, 0xAB, 0xCD])
        try DatabaseService.shared.insertAttachment(a)

        let fetched = try XCTUnwrap(DatabaseService.shared.attachment(id: "X1"))
        XCTAssertEqual(fetched.data, Data([0xFF, 0xD8, 0xFF, 0xAB, 0xCD]))
        XCTAssertNil(try DatabaseService.shared.attachment(id: "nope"))
    }

    // MARK: - ImageProcessing

    private func solidPNG(width: Int, height: Int) -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemPurple.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testDownscaleShrinksOversizedImageToJPEG() {
        let src = solidPNG(width: 4000, height: 3000)
        let out = ImageProcessing.downscaledJPEG(from: src, maxEdge: 2048)
        let encoded = try! XCTUnwrap(out)
        // Longest edge clamped to maxEdge; aspect preserved.
        XCTAssertEqual(max(encoded.width, encoded.height), 2048)
        XCTAssertEqual(encoded.height, 1536)   // 3000 * (2048/4000)
        // JPEG SOI marker.
        XCTAssertEqual(Array(encoded.data.prefix(2)), [0xFF, 0xD8])
    }

    func testDownscaleNeverUpscales() {
        let src = solidPNG(width: 100, height: 80)
        let out = try! XCTUnwrap(ImageProcessing.downscaledJPEG(from: src, maxEdge: 2048))
        XCTAssertEqual(out.width, 100)
        XCTAssertEqual(out.height, 80)
    }

    func testThumbnailProducesSmallJPEG() {
        let src = solidPNG(width: 1200, height: 1200)
        let thumb = try! XCTUnwrap(ImageProcessing.thumbnailJPEG(from: src, edge: 256))
        XCTAssertEqual(Array(thumb.prefix(2)), [0xFF, 0xD8])
        XCTAssertLessThan(thumb.count, src.count, "thumbnail should be smaller than the source")
    }

    func testRejectsNonImageData() {
        XCTAssertNil(ImageProcessing.downscaledJPEG(from: Data("not an image".utf8)))
        XCTAssertNil(ImageProcessing.thumbnailJPEG(from: Data([0x00, 0x01, 0x02])))
    }
}
