import Foundation
import CryptoKit

enum HashAlgorithm: String, CaseIterable, Identifiable, Codable {
    case sha1   = "SHA-1"
    case md5    = "MD5"
    case sha256 = "SHA-256"
    /// C4 ID — SHA-512 of file content, base58-encoded with the
    /// C4-specific alphabet (no 0/O/I/l), prefixed `c4`, zero-padded
    /// (`1` = base58 zero) to a fixed 90-char width. Required for
    /// Netflix Originals delivery alongside ASC-MHL v2.0.
    case c4     = "C4"

    var id: String { rawValue }

    /// MHL v1.1 element name for this algorithm. C4 isn't part of
    /// the v1.1 spec; the legacy writer skips it.
    var mhlElement: String {
        switch self {
        case .sha1:   return "sha1"
        case .md5:    return "md5"
        case .sha256: return "sha256"
        case .c4:     return "c4"
        }
    }
    /// True when the legacy MHL v1.1 writer can emit this algorithm.
    /// C4 is ASC-MHL-only.
    var legacyMHLCompatible: Bool {
        switch self {
        case .sha1, .md5, .sha256: return true
        case .c4: return false
        }
    }
}

/// Chunked streaming file hasher. 4 MB chunks match the
/// MasterClipper pattern (see `feedback_purplededup_perf`-adjacent
/// guidance — large enough to amortize syscall overhead, small enough
/// to keep peak memory bounded).
enum HashingService {
    static let chunkSize = 4 * 1024 * 1024

    /// Hash a file with the requested algorithm. `onProgress` is called
    /// off the main actor with the number of bytes read so far. Returns
    /// the lowercase hex digest.
    static func hash(file url: URL,
                     algorithm: HashAlgorithm,
                     onProgress: ((Int64) -> Void)? = nil) throws -> String {
        switch algorithm {
        case .sha1:   return try streamHash(file: url, hasher: Insecure.SHA1(), onProgress: onProgress)
        case .md5:    return try streamHash(file: url, hasher: Insecure.MD5(),  onProgress: onProgress)
        case .sha256: return try streamHash(file: url, hasher: SHA256(),         onProgress: onProgress)
        case .c4:
            // C4 = SHA-512 digest, base58-encoded (C4 alphabet),
            // prefixed `c4`, padded to 90 chars total.
            let digest = try streamRawDigest(file: url, hasher: SHA512(),
                                              onProgress: onProgress)
            return Base58.c4ID(from: digest)
        }
    }

    /// Streaming variant that returns the raw digest bytes instead of
    /// hex — needed by C4 which encodes the bytes in a custom alphabet.
    private static func streamRawDigest<H: HashFunction>(
        file url: URL,
        hasher initial: H,
        onProgress: ((Int64) -> Void)?
    ) throws -> Data {
        var hasher = initial
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var bytesRead: Int64 = 0
        while true {
            let chunk = autoreleasepool { () -> Data in
                handle.readData(ofLength: chunkSize)
            }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            bytesRead += Int64(chunk.count)
            onProgress?(bytesRead)
        }
        return Data(hasher.finalize())
    }

    private static func streamHash<H: HashFunction>(
        file url: URL,
        hasher initial: H,
        onProgress: ((Int64) -> Void)?
    ) throws -> String {
        var hasher = initial
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var bytesRead: Int64 = 0
        while true {
            let chunk = autoreleasepool { () -> Data in
                handle.readData(ofLength: chunkSize)
            }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            bytesRead += Int64(chunk.count)
            onProgress?(bytesRead)
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// C4 base58 encoder. The C4 alphabet excludes 0, O, I, l to avoid
/// look-alike confusion. A C4 ID is a SHA-512 digest expressed as a
/// base58 string in this alphabet, prefixed `c4`, zero-padded (`1` =
/// base58 zero) to exactly 90 characters.
///
/// We do bignum division by 58 over the 64-byte digest as an array
/// of UInt8 — simpler than pulling in a BigInt dependency and fast
/// enough for the hash-once-per-file workload.
enum Base58 {
    static let c4Alphabet: [Character] = Array(
        "123456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ"
    )

    /// Convert a SHA-512 digest (64 bytes) to a C4 ID. The result is
    /// always exactly 90 characters: `c4` + 88 base58 chars.
    static func c4ID(from digest: Data) -> String {
        var bytes = [UInt8](digest)
        var encoded: [Character] = []
        // Repeatedly divide the big-endian byte array by 58, pushing
        // each remainder through the C4 alphabet. Done when the
        // entire array is zero.
        while !bytes.allSatisfy({ $0 == 0 }) {
            var remainder: UInt32 = 0
            for i in 0..<bytes.count {
                let acc = remainder * 256 + UInt32(bytes[i])
                bytes[i] = UInt8(acc / 58)
                remainder = acc % 58
            }
            encoded.append(c4Alphabet[Int(remainder)])
        }
        // Pad to 88 chars with the "zero" digit. Reverse so the
        // most-significant digit is first.
        while encoded.count < 88 {
            encoded.append(c4Alphabet[0])
        }
        return "c4" + String(encoded.reversed())
    }
}
