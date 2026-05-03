import Foundation
import GRDB

enum PostingStatus: String, Codable, CaseIterable, Hashable {
    case pending
    case posted
    case skipped
    case removed
}

struct ClipPosting: Codable, FetchableRecord, PersistableRecord, Hashable {
    var clipId: String
    var siteId: Int64
    var postedDate: String?
    var status: String                          // PostingStatus.rawValue
    var notes: String
    var createdAt: String
    var updatedAt: String

    static let databaseTableName = "clip_postings"

    enum CodingKeys: String, CodingKey {
        case clipId = "clip_id"
        case siteId = "site_id"
        case postedDate = "posted_date"
        case status
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var isPosted: Bool {
        statusEnum == .posted && (postedDate ?? "").isEmpty == false
    }

    var statusEnum: PostingStatus {
        PostingStatus(rawValue: status) ?? .pending
    }
}
