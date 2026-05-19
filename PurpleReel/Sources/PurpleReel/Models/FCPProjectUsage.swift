import Foundation
import GRDB

/// C25 — one row in the `fcp_project_usage` table. Records that a
/// specific asset has been referenced from a Final Cut Pro project
/// (learned by the FCPXML importer). Composite key `(assetId,
/// projectName)` so re-importing the same FCPXML idempotently
/// refreshes the row rather than creating duplicates.
///
/// - `eventName`: optional FCP event the project lived under
///   ("My Event") — useful for the inspector when project names
///   collide across events.
/// - `libraryPath`: the original `.fcpxmld` file the importer read.
///   Not the underlying `.fcpbundle` (PurpleReel doesn't parse
///   those — see C25 CHANGELOG note). Nullable because the
///   importer may eventually accept stream input.
struct FCPProjectUsage: Codable, Identifiable, Equatable, Hashable,
                        FetchableRecord, PersistableRecord {
    var assetId: Int64
    var projectName: String
    var eventName: String?
    var libraryPath: String?
    var importedAt: Date

    /// SwiftUI Identifiable conformance — composite of the natural
    /// primary key so each row renders uniquely in lists.
    var id: String { "\(assetId)#\(projectName)" }

    static let databaseTableName = "fcp_project_usage"

    enum CodingKeys: String, CodingKey {
        case assetId, projectName, eventName, libraryPath, importedAt
    }
}
