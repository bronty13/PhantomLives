import Foundation
import UniformTypeIdentifiers

/// One media file found on disk during a scan. A `Sendable` value type so it can cross from
/// the background discovery task to the main-actor persistence step. Pure data — no GRDB.
struct ScannedFile: Sendable, Equatable {
    let path: String
    let name: String
    let type: MediaType
    let size: Int64?
    let modifiedAt: String?
}

/// Recursively discovers photos, videos, and audio under a folder. Pure and synchronous —
/// callers run it inside a detached task. Classification is by UTType conformance (not file
/// extension), so HEIC/HEIF, ProRes, etc. are recognized correctly. Hidden files and the
/// insides of packages (`.app`, `.photoslibrary`) are skipped.
enum MediaDiscoveryService {

    private static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .contentTypeKey
    ]

    static func scan(root: URL) -> [ScannedFile] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [ScannedFile] = []
        for case let url as URL in enumerator {
            guard let rv = try? url.resourceValues(forKeys: resourceKeys),
                  rv.isRegularFile == true,
                  let type = classify(contentType: rv.contentType)
            else { continue }

            results.append(ScannedFile(
                path: url.standardizedFileURL.path,
                name: url.lastPathComponent,
                type: type,
                size: rv.fileSize.map(Int64.init),
                modifiedAt: rv.contentModificationDate.map(Self.iso)
            ))
        }
        return results
    }

    /// Map a UTType to one of PurplePeek's three media kinds, or nil to ignore the file.
    /// Order matters: image first, then moving image, then audio (a file conforming to
    /// `.movie` may also surface audio traits).
    private static func classify(contentType: UTType?) -> MediaType? {
        guard let ct = contentType else { return nil }
        if ct.conforms(to: .image) { return .photo }
        if ct.conforms(to: .movie) || ct.conforms(to: .video) { return .video }
        if ct.conforms(to: .audio) { return .audio }
        return nil
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    private static func iso(_ date: Date) -> String { isoFormatter.string(from: date) }
}
