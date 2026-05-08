import Foundation
import GRDB

/// Edge in the matter-relation graph. `kind` is `"depends_on"` or
/// `"related"` — depends_on is directional (this Matter waits on the other),
/// related is undirected (we still write a single row per direction the user
/// authors and surface them symmetrically in the UI).
struct MatterLink: Codable, Hashable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "matter_link"

    var matterId: String
    var relatedMatterId: String
    var kind: String

    enum CodingKeys: String, CodingKey {
        case kind
        case matterId = "matter_id"
        case relatedMatterId = "related_matter_id"
    }

    enum Kind: String, CaseIterable, Identifiable {
        case dependsOn = "depends_on"
        case related   = "related"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .dependsOn: return "Depends on"
            case .related:   return "Related"
            }
        }
    }
}
