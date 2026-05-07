import Foundation
import CryptoKit
import UniformTypeIdentifiers

/// Hash + ingest helpers for `Attachment`. SHA1 is the spec-mandated
/// integrity-check algorithm; MD5 + SHA256 are stored alongside for display
/// and historical compatibility.
enum AttachmentService {

    struct Hashes: Equatable {
        let md5: String
        let sha1: String
        let sha256: String
    }

    static func hashes(for data: Data) -> Hashes {
        let md5    = Insecure.MD5.hash(data: data)
        let sha1   = Insecure.SHA1.hash(data: data)
        let sha256 = SHA256.hash(data: data)
        return Hashes(md5: hex(md5), sha1: hex(sha1), sha256: hex(sha256))
    }

    private static func hex<H: Sequence>(_ h: H) -> String where H.Element == UInt8 {
        h.map { String(format: "%02x", $0) }.joined()
    }

    /// Build an `Attachment` ready to insert. Computes all three hashes.
    @MainActor
    static func ingest(fileURL: URL, matterId: String) throws -> Attachment {
        let data = try Data(contentsOf: fileURL)
        let h = hashes(for: data)
        let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        return Attachment(
            id: UUID().uuidString,
            matterId: matterId,
            filename: fileURL.lastPathComponent,
            sizeBytes: Int64(data.count),
            mimeType: mime,
            data: data,
            md5: h.md5,
            sha1: h.sha1,
            sha256: h.sha256,
            addedAt: Date(),
            lastVerifiedAt: Date(),
            lastVerifyOk: true
        )
    }

    /// Recompute SHA1 over the BLOB and compare against the stored value.
    /// Returns `true` if the blob is intact. Side-effect-free — the caller
    /// updates the persisted verification record.
    static func verify(_ attachment: Attachment) -> Bool {
        let recomputed = hex(Insecure.SHA1.hash(data: attachment.data))
        return recomputed.caseInsensitiveCompare(attachment.sha1) == .orderedSame
    }
}
