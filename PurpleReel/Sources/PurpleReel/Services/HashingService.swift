import Foundation
import CryptoKit

enum HashAlgorithm: String, CaseIterable, Identifiable, Codable {
    case sha1   = "SHA-1"
    case md5    = "MD5"
    case sha256 = "SHA-256"

    var id: String { rawValue }

    /// MHL v1.1 element name for this algorithm.
    var mhlElement: String {
        switch self {
        case .sha1:   return "sha1"
        case .md5:    return "md5"
        case .sha256: return "sha256"
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
        }
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
            let chunk = try autoreleasepool { () -> Data in
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
