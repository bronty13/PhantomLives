import Foundation
import GRDB

/// A timestamped, operator-attributed note attached to a clip. New as of v14.
///
/// This replaces the old single-blob `clips.notes` text column for everyday
/// note-taking. The blob still exists (for backwards compat and the various
/// `[Editing YYYY-MM-DD]` / `[Posted …]` / `[Status …]` markers that other
/// code writes), but the editor surface for hand-written notes lives here.
struct ClipNote: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Hashable {
    var id: Int64?
    var clipId: String
    var body: String
    var operatorName: String
    var createdAt: String          // ISO-8601, see DatabaseService.isoNow()
    var updatedAt: String

    static let databaseTableName = "clip_notes"

    enum CodingKeys: String, CodingKey {
        case id
        case clipId       = "clip_id"
        case body
        case operatorName = "operator_name"
        case createdAt    = "created_at"
        case updatedAt    = "updated_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
