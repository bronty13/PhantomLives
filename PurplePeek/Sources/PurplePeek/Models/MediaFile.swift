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
    var title: String?
    var caption: String?
    var importedAt: String?        // photos/videos imported to Photos
    var exportedAt: String?        // audio copied to the Kept Audio Export folder
    var deletedAt: String?
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
        case title
        case caption
        case importedAt = "imported_at"
        case exportedAt = "exported_at"
        case deletedAt = "deleted_at"
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
}
