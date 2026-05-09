import XCTest
import CryptoKit
@testable import PurpleDedupCore

final class ContentHasherTests: XCTestCase {

    func testIdenticalContentHashesEqual() throws {
        let root = try TestFixtures.makeTempDir("hash-equal")
        defer { TestFixtures.cleanup(root) }

        let payload = Data(repeating: 0xAB, count: 4096)
        let a = try TestFixtures.write(payload, to: root.appendingPathComponent("a.bin"))
        let b = try TestFixtures.write(payload, to: root.appendingPathComponent("b.bin"))

        let hasher = ContentHasher()
        XCTAssertEqual(try hasher.hexHash(fileAt: a), try hasher.hexHash(fileAt: b))
    }

    func testDifferentContentHashesDiffer() throws {
        let root = try TestFixtures.makeTempDir("hash-diff")
        defer { TestFixtures.cleanup(root) }

        let a = try TestFixtures.write(Data(repeating: 0xAB, count: 4096), to: root.appendingPathComponent("a.bin"))
        let b = try TestFixtures.write(Data(repeating: 0xAC, count: 4096), to: root.appendingPathComponent("b.bin"))

        let hasher = ContentHasher()
        XCTAssertNotEqual(try hasher.hexHash(fileAt: a), try hasher.hexHash(fileAt: b))
    }

    func testEmptyFileDigestPinnedPerAlgorithm() throws {
        // Pin the empty-file digest for every supported algorithm. If anyone swaps
        // the implementation, this catches the drift before it ships.
        let root = try TestFixtures.makeTempDir("hash-empty")
        defer { TestFixtures.cleanup(root) }
        let f = try TestFixtures.write(Data(), to: root.appendingPathComponent("empty.bin"))

        let expected: [HashAlgorithm: String] = [
            .sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            .sha384: "38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b",
            .sha512: "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e",
            .sha1:   "da39a3ee5e6b4b0d3255bfef95601890afd80709",
            .md5:    "d41d8cd98f00b204e9800998ecf8427e",
        ]
        for algo in HashAlgorithm.allCases {
            let hex = try ContentHasher(algorithm: algo).hexHash(fileAt: f)
            XCTAssertEqual(hex, expected[algo], "\(algo) of empty file mismatch")
        }
    }

    func testStreamsLargerThanChunkSize() throws {
        // Hashing larger-than-one-chunk inputs exercises the read loop. We assert that
        // the result matches a reference SHA computed over the same bytes in one shot.
        let root = try TestFixtures.makeTempDir("hash-large")
        defer { TestFixtures.cleanup(root) }

        let bytes = (0..<(ContentHasher.chunkSize * 3 + 17)).map { UInt8($0 % 251) }
        let payload = Data(bytes)
        let f = try TestFixtures.write(payload, to: root.appendingPathComponent("big.bin"))

        // Test the SHA-256 path explicitly — the streamed-vs-one-shot equivalence is
        // the same property for any hash, and SHA-256 has the most distinctive output
        // length to spot truncation bugs against.
        let streamed = try ContentHasher(algorithm: .sha256).hash(fileAt: f)

        var ref = SHA256()
        ref.update(data: payload)
        let reference = Data(ref.finalize())

        XCTAssertEqual(streamed, reference)
    }
}
