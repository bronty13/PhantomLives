import Foundation
import GRDB

/// One discovered media file and all the decisions made about it. Persisted in the
/// `media_files` table, keyed by `id` (a UUID) with a UNIQUE constraint on `filePath` so a
/// re-scan of the same path updates the existing row rather than duplicating it.
///
/// `keep` uses SQLite's tri-state integer: NULL = undecided, 1 = keep, 0 = skip. The
/// `keepDecision` computed property bridges that to a Swift `Bool?` for the UI.
struct MediaFile: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    var id: String
    var scanRoot: String
    var filePath: String
    var fileName: String
    var fileType: String           // MediaType.rawValue: "photo" | "video" | "audio"
    var fileSize: Int64?
    var fileModifiedAt: String?
    var keep: Int?                 // NULL = undecided, 1 = keep, 0 = skip
    var isFavorite: Bool
    var isHidden: Bool = false     // mirrors PHAsset.isHidden (added in migration v2)
    var title: String?
    var caption: String?
    var importedAt: String?        // photos/videos imported to Photos
    var exportedAt: String?        // audio copied to the Kept Audio Export folder
    var deletedAt: String?
    var missingAt: String? = nil   // set by a re-scan when the file vanished from disk (migration v3)
    var contentHash: String? = nil // SHA-256 hex for exact-duplicate detection (migration v5)
    var photosAssetId: String?
    var createdAt: String
    var updatedAt: String

    static let databaseTableName = "media_files"

    enum CodingKeys: String, CodingKey {
        case id
        case scanRoot = "scan_root"
        case filePath = "file_path"
        case fileName = "file_name"
        case fileType = "file_type"
        case fileSize = "file_size"
        case fileModifiedAt = "file_modified_at"
        case keep
        case isFavorite = "is_favorite"
        case isHidden = "is_hidden"
        case title
        case caption
        case importedAt = "imported_at"
        case exportedAt = "exported_at"
        case deletedAt = "deleted_at"
        case missingAt = "missing_at"
        case contentHash = "content_hash"
        case photosAssetId = "photos_asset_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: - Convenience

    /// Tri-state keep decision as a Swift optional Bool (nil = undecided).
    var keepDecision: Bool? {
        get { keep.map { $0 != 0 } }
        set { keep = newValue.map { $0 ? 1 : 0 } }
    }

    var mediaType: MediaType { MediaType(rawValue: fileType) ?? .photo }
    var fileURL: URL { URL(fileURLWithPath: filePath) }
    var isDeleted: Bool { deletedAt != nil }
    var isImported: Bool { importedAt != nil }
    /// True when a re-scan found the file gone from disk (it may still reappear).
    var isMissing: Bool { missingAt != nil }

    /// `fileModifiedAt` as a real Date, tolerating both stored dialects: the local scanner
    /// writes local-time ISO without a zone ("2026-06-15T18:51:32"), PeekServer writes UTC
    /// with Z ("2026-06-15T18:51:32Z"). nil when absent/unparseable — such items fail any
    /// active date window (unknown age ≠ recent). Backs the toolbar Date filter.
    var modifiedDate: Date? {
        guard let s = fileModifiedAt, !s.isEmpty else { return nil }
        // Dispatch on the suffix — DateFormatter is lenient about a missing quoted 'Z', so
        // trying the UTC pattern first would silently mis-zone the local dialect by hours.
        return s.hasSuffix("Z") ? Self.utcDateFormatter.date(from: s)
                                : Self.localDateFormatter.date(from: s)
    }

    private static let utcDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let localDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()
}
