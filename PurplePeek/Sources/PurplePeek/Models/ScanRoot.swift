import Foundation
import GRDB

/// A folder the user has scanned. Keyed by its absolute `path`. `totalFiles` and
/// `lastScannedAt` are refreshed on each scan; `label` is an optional user-friendly name
/// shown in the sidebar and Scan Roots settings.
struct ScanRoot: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    var path: String
    var lastScannedAt: String
    var totalFiles: Int
    var label: String?

    static let databaseTableName = "scan_roots"

    var id: String { path }

    enum CodingKeys: String, CodingKey {
        case path
        case lastScannedAt = "last_scanned_at"
        case totalFiles = "total_files"
        case label
    }

    var url: URL { URL(fileURLWithPath: path) }
    /// Display name: the user label if set, else the folder's last path component.
    var displayName: String {
        if let label, !label.isEmpty { return label }
        return url.lastPathComponent
    }
}
