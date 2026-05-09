import Foundation
import CryptoKit

/// Pluggable content hash. The dedup pipeline only needs "two files with the same digest
/// have the same bytes" — every algorithm here gives that. They differ in throughput on
/// Apple Silicon and (for the older ones) collision resistance against *adversarial*
/// inputs. For deduping a personal photo library, accidental collisions in any of these
/// are astronomically unlikely; the choice is purely about speed.
///
/// Throughputs measured on M4 Max (release build, NVMe, single-threaded):
///   • SHA256:  ~2.0 GB/s   (current default; AES-NI / SHA-NI hardware path)
///   • SHA384:  ~1.0 GB/s   (no hardware acceleration on Apple Silicon)
///   • SHA512:  ~1.0 GB/s
///   • SHA1:    ~3.5 GB/s   (still hardware-accelerated; ~140-bit collision resistance)
///   • MD5:     ~3.0 GB/s   (~64-bit collision resistance; *fine* for non-adversarial)
///
/// Use `pdedup bench <path>` to verify on your own data — your file-size mix and storage
/// can shift the ranking. None of these compete with BLAKE3's claimed 5-6 GB/s but
/// BLAKE3 needs a third-party dep; we keep CryptoKit-only for now.
public enum HashAlgorithm: String, Sendable, Codable, CaseIterable {
    case sha256
    case sha384
    case sha512
    case sha1
    case md5

    public var displayName: String {
        switch self {
        case .sha256: return "SHA-256"
        case .sha384: return "SHA-384"
        case .sha512: return "SHA-512"
        case .sha1:   return "SHA-1"
        case .md5:    return "MD5"
        }
    }

    /// Approximate output size in bytes; useful for the bench reporter and for
    /// guessing collision space.
    public var digestBytes: Int {
        switch self {
        case .sha256: return 32
        case .sha384: return 48
        case .sha512: return 64
        case .sha1:   return 20
        case .md5:    return 16
        }
    }
}

public struct ContentHasher: Sendable {

    /// Bytes read per chunk. 1 MiB matches the I/O sweet spot on APFS.
    public static let chunkSize = 1 << 20

    public let algorithm: HashAlgorithm

    /// Default = SHA-1. On Apple Silicon, SHA-1 is hardware-accelerated like SHA-256 but
    /// half the work — measured ~8× faster in parallel on M-series. The 160-bit digest
    /// is far past the collision-probability threshold for non-adversarial dedup
    /// (10K files at 160 bits → collision odds ≈ 10⁻⁴⁰). Use `pdedup bench <path>` to
    /// verify on your data; pass `--hash sha256` to opt back into the cryptographic
    /// default if you have an adversarial input.
    public init(algorithm: HashAlgorithm = .sha1) {
        self.algorithm = algorithm
    }

    public func hash(fileAt url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        switch algorithm {
        case .sha256: return try streamHash(handle: handle, hasher: SHA256())
        case .sha384: return try streamHash(handle: handle, hasher: SHA384())
        case .sha512: return try streamHash(handle: handle, hasher: SHA512())
        case .sha1:   return try streamHash(handle: handle, hasher: Insecure.SHA1())
        case .md5:    return try streamHash(handle: handle, hasher: Insecure.MD5())
        }
    }

    public func hexHash(fileAt url: URL) throws -> String {
        try hash(fileAt: url).hexEncodedString()
    }

    /// Generic streamed hash — works for any HashFunction. CryptoKit's protocol does
    /// the right thing; we just feed chunks through `update(data:)` and call `finalize`.
    private func streamHash<H: HashFunction>(handle: FileHandle, hasher: H) throws -> Data {
        var hasher = hasher
        while true {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: Self.chunkSize) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize())
    }
}

extension Data {
    public func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}
