import Foundation

/// JSON-friendly report for a `pdedup audit` run. Mirrors `ScanReport`'s shape and
/// versioning so downstream consumers parse both the same way.
public struct AuditReport: Codable, Sendable {

    public struct File: Codable, Sendable {
        public let path: String
        public let sizeBytes: Int64
        public let modificationTimeISO: String
        /// "in_photos_exact" | "likely_in_photos_perceptual" |
        /// "likely_in_photos_filename" | "missing"
        public let classification: String
        public let contentHash: String?
        /// Present only on perceptual matches — the OR-of-distances Hamming value.
        public let perceptualDistance: Int?
    }

    public let appName: String
    public let appVersion: String
    public let generatedAtISO: String
    public let folder: String
    public let photosLibrary: String
    public let matchMode: String
    public let totalFilesAudited: Int
    public let inPhotosCount: Int
    public let missingCount: Int
    public let unreadableCount: Int
    public let photosIndexedCount: Int
    public let files: [File]
    public let unreadable: [String]

    public static func from(_ result: AuditEngine.AuditResult) -> AuditReport {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let files: [File] = result.files.map { f in
            let kind: String
            var distance: Int?
            switch f.classification {
            case .inPhotosExact:                      kind = "in_photos_exact"
            case .likelyInPhotosPerceptual(let d):    kind = "likely_in_photos_perceptual"; distance = d
            case .likelyInPhotosFilename:             kind = "likely_in_photos_filename"
            case .missing:                            kind = "missing"
            }
            return File(
                path: f.url.path,
                sizeBytes: f.sizeBytes,
                modificationTimeISO: iso.string(from: f.modificationTime),
                classification: kind,
                contentHash: f.contentHashHex,
                perceptualDistance: distance
            )
        }

        return AuditReport(
            appName: PurpleDedup.appName,
            appVersion: PurpleDedup.coreVersion,
            generatedAtISO: iso.string(from: Date()),
            folder: result.folder.path,
            photosLibrary: result.photosLibrary.path,
            matchMode: result.matchMode.rawValue,
            totalFilesAudited: result.files.count,
            inPhotosCount: result.inPhotos.count,
            missingCount: result.missing.count,
            unreadableCount: result.unreadable.count,
            photosIndexedCount: result.photosIndexedCount,
            files: files,
            unreadable: result.unreadable.map { $0.path }
        )
    }

    public func toJSONData(pretty: Bool = true) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try enc.encode(self)
    }
}
