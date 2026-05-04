import Foundation
import CryptoKit

/// Streams a file through MD5, SHA-1, and SHA-256 in a single pass —
/// reads in 4 MB chunks so multi-GB clips don't blow memory and so the
/// app stays responsive while a hash runs. CryptoKit's MD5 and SHA-1
/// live under `Insecure` (they're not safe for crypto, but they're fine
/// for file-integrity fingerprints, which is what we want here).
@MainActor
enum HashService {

    /// Hex-encoded digests for one file.
    struct Hashes: Equatable {
        let md5: String
        let sha1: String
        let sha256: String
        let sizeBytes: Int64

        var allEmpty: Bool {
            md5.isEmpty && sha1.isEmpty && sha256.isEmpty
        }
    }

    enum HashError: LocalizedError {
        case fileMissing(String)
        case openFailed(String, underlying: String)
        case readFailed(String, underlying: String)

        var errorDescription: String? {
            switch self {
            case .fileMissing(let p):
                return "File not found: \(p)"
            case .openFailed(let p, let u):
                return "Couldn't open \(p): \(u)"
            case .readFailed(let p, let u):
                return "Read failed for \(p): \(u)"
            }
        }
    }

    /// 4 MB. Big enough to amortize syscall overhead, small enough that
    /// memory stays bounded for any sensible input.
    nonisolated private static let chunkSize = 4 * 1024 * 1024

    /// Compute all three hashes for `filePath` in a single streaming
    /// pass. Off-main work — call from a background Task; the
    /// `@MainActor` annotation on the enum is only there because the
    /// rest of the services use it for consistency, not because the
    /// inner work needs to be on the main actor.
    nonisolated static func hash(filePath: String) async throws -> Hashes {
        let fm = FileManager.default
        guard fm.fileExists(atPath: filePath) else {
            throw HashError.fileMissing(filePath)
        }

        let url = URL(fileURLWithPath: filePath)
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw HashError.openFailed(filePath, underlying: error.localizedDescription)
        }
        defer { try? handle.close() }

        var md5    = Insecure.MD5()
        var sha1   = Insecure.SHA1()
        var sha256 = SHA256()
        var totalBytes: Int64 = 0

        do {
            while true {
                guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                    break
                }
                md5.update(data: chunk)
                sha1.update(data: chunk)
                sha256.update(data: chunk)
                totalBytes &+= Int64(chunk.count)
            }
        } catch {
            throw HashError.readFailed(filePath, underlying: error.localizedDescription)
        }

        return Hashes(
            md5:    md5.finalize().hexString(),
            sha1:   sha1.finalize().hexString(),
            sha256: sha256.finalize().hexString(),
            sizeBytes: totalBytes
        )
    }
}

private extension Sequence where Element == UInt8 {
    func hexString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}
