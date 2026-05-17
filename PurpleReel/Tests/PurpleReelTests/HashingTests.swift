import XCTest
@testable import PurpleReel

final class HashingTests: XCTestCase {

    /// Known SHA-1 vector: empty input.
    /// "" → da39a3ee5e6b4b0d3255bfef95601890afd80709
    func testEmptyFileSHA1() throws {
        let url = try writeTempFile(data: Data())
        defer { try? FileManager.default.removeItem(at: url) }
        let digest = try HashingService.hash(file: url, algorithm: .sha1)
        XCTAssertEqual(digest, "da39a3ee5e6b4b0d3255bfef95601890afd80709")
    }

    /// Known SHA-1 vector (FIPS 180-4 §A.1):
    /// "abc" → a9993e364706816aba3e25717850c26c9cd0d89d
    func testKnownASCIIVectorSHA1() throws {
        let url = try writeTempFile(data: Data("abc".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let digest = try HashingService.hash(file: url, algorithm: .sha1)
        XCTAssertEqual(digest, "a9993e364706816aba3e25717850c26c9cd0d89d")
    }

    /// "abc" → MD5 900150983cd24fb0d6963f7d28e17f72
    func testKnownASCIIVectorMD5() throws {
        let url = try writeTempFile(data: Data("abc".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let digest = try HashingService.hash(file: url, algorithm: .md5)
        XCTAssertEqual(digest, "900150983cd24fb0d6963f7d28e17f72")
    }

    /// "abc" → SHA-256 ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
    func testKnownASCIIVectorSHA256() throws {
        let url = try writeTempFile(data: Data("abc".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let digest = try HashingService.hash(file: url, algorithm: .sha256)
        XCTAssertEqual(digest, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    /// Chunked streaming must produce the same digest as a single-shot
    /// hash of the same bytes — guards against the 4 MB chunking
    /// introducing alignment bugs.
    func testChunkedMatchesSingleShot() throws {
        // 9 MB of pseudo-random data crosses two chunk boundaries.
        var data = Data(count: 9 * 1024 * 1024)
        data.withUnsafeMutableBytes { ptr in
            for i in 0..<ptr.count {
                ptr.storeBytes(of: UInt8((i * 31) & 0xff), toByteOffset: i, as: UInt8.self)
            }
        }
        let url = try writeTempFile(data: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let streamingSHA1 = try HashingService.hash(file: url, algorithm: .sha1)
        // Reference: hash the same bytes via a single CryptoKit call.
        let referenceSHA1: String = {
            var hasher = Insecure.SHA1()
            hasher.update(data: data)
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }()
        XCTAssertEqual(streamingSHA1, referenceSHA1)
    }

    /// Progress callback should fire and end at exactly file size.
    func testProgressCallbackEndsAtFileSize() throws {
        let bytes = Data(repeating: 0x42, count: 5 * 1024 * 1024 + 17)
        let url = try writeTempFile(data: bytes)
        defer { try? FileManager.default.removeItem(at: url) }
        var lastReported: Int64 = -1
        _ = try HashingService.hash(file: url, algorithm: .sha1, onProgress: { n in
            lastReported = n
        })
        XCTAssertEqual(lastReported, Int64(bytes.count))
    }

    // MARK: - Helpers

    private func writeTempFile(data: Data) throws -> URL {
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("purplereel-hash-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let url = URL(fileURLWithPath: dir).appendingPathComponent("input.bin")
        try data.write(to: url)
        return url
    }
}

// Re-import locally so the reference computation in
// testChunkedMatchesSingleShot doesn't need to round-trip through the
// service's public API.
import CryptoKit
