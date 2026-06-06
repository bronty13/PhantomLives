import Foundation
import CryptoKit

/// File / data digests. Surfaced in the GUI's entry inspector and `parc hash`.
/// Streams the file so hashing a multi-gigabyte archive stays O(1) in memory.
public enum HashAlgorithm: String, CaseIterable, Sendable {
    case md5, sha1, sha256, sha512

    public var displayName: String {
        switch self {
        case .md5: return "MD5"
        case .sha1: return "SHA-1"
        case .sha256: return "SHA-256"
        case .sha512: return "SHA-512"
        }
    }
}

public enum Hasher {
    private static let chunk = 1 << 20  // 1 MiB

    public static func hash(_ url: URL, algorithm: HashAlgorithm) throws -> String {
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        switch algorithm {
        case .md5:    return stream(fh, into: Insecure.MD5())
        case .sha1:   return stream(fh, into: Insecure.SHA1())
        case .sha256: return stream(fh, into: SHA256())
        case .sha512: return stream(fh, into: SHA512())
        }
    }

    public static func hash(_ data: Data, algorithm: HashAlgorithm) -> String {
        switch algorithm {
        case .md5:    return hex(Insecure.MD5.hash(data: data))
        case .sha1:   return hex(Insecure.SHA1.hash(data: data))
        case .sha256: return hex(SHA256.hash(data: data))
        case .sha512: return hex(SHA512.hash(data: data))
        }
    }

    private static func stream<H: HashFunction>(_ fh: FileHandle, into hasher: H) -> String {
        var h = hasher
        while case let data = fh.readData(ofLength: chunk), !data.isEmpty {
            h.update(data: data)
        }
        return hex(h.finalize())
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
