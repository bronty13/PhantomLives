import XCTest
@testable import PurpleTracker

@MainActor
final class AttachmentHashTests: XCTestCase {

    func testKnownVectorsForEmptyData() {
        let h = AttachmentService.hashes(for: Data())
        XCTAssertEqual(h.md5,    "d41d8cd98f00b204e9800998ecf8427e")
        XCTAssertEqual(h.sha1,   "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        XCTAssertEqual(h.sha256, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testKnownVectorsForAbc() {
        let data = "abc".data(using: .utf8)!
        let h = AttachmentService.hashes(for: data)
        XCTAssertEqual(h.md5,    "900150983cd24fb0d6963f7d28e17f72")
        XCTAssertEqual(h.sha1,   "a9993e364706816aba3e25717850c26c9cd0d89d")
        XCTAssertEqual(h.sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testVerifyDetectsMismatch() {
        let original = "hello world".data(using: .utf8)!
        let h = AttachmentService.hashes(for: original)
        var att = Attachment(
            id: "x", matterId: "m", filename: "f.txt",
            sizeBytes: Int64(original.count), mimeType: "text/plain",
            data: original, md5: h.md5, sha1: h.sha1, sha256: h.sha256,
            addedAt: Date(), lastVerifiedAt: nil, lastVerifyOk: true
        )
        XCTAssertTrue(AttachmentService.verify(att))

        // Tamper with the BLOB without updating the stored sha1.
        att.data = "hello WORLD".data(using: .utf8)!
        XCTAssertFalse(AttachmentService.verify(att))
    }
}
