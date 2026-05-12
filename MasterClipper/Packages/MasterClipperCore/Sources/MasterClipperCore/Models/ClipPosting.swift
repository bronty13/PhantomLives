import Foundation
import GRDB

public enum PostingStatus: String, Codable, CaseIterable, Hashable {
    case pending
    case posted
    case skipped
    case removed
}

public struct ClipPosting: Codable, FetchableRecord, PersistableRecord, Hashable {
    public var clipId: String
    public var siteId: Int64
    public var postedDate: String?
    public var status: String                          // PostingStatus.rawValue
    public var notes: String
    public var createdAt: String
    public var updatedAt: String

    public static let databaseTableName = "clip_postings"

    enum CodingKeys: String, CodingKey {
        case clipId = "clip_id"
        case siteId = "site_id"
        case postedDate = "posted_date"
        case status
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        clipId: String,
        siteId: Int64,
        postedDate: String? = nil,
        status: String,
        notes: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.clipId = clipId
        self.siteId = siteId
        self.postedDate = postedDate
        self.status = status
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isPosted: Bool {
        statusEnum == .posted && (postedDate ?? "").isEmpty == false
    }

    public var statusEnum: PostingStatus {
        PostingStatus(rawValue: status) ?? .pending
    }
}
