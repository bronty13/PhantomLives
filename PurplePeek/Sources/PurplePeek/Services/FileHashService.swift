import Foundation
import CryptoKit

/// Computes a content hash for exact-duplicate detection. Pure and synchronous — callers run
/// it inside a detached task. Streams the file in chunks so hashing a large video never loads
/// the whole thing into memory.
enum FileHashService {

    /// SHA-256 of the file's bytes as a lowercase hex string, or nil if it can't be read.
    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 1 << 20   // 1 MB
        while true {
            guard let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
