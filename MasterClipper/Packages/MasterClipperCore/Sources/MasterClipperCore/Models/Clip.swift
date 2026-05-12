import Foundation
import GRDB

public enum ClipStatus: String, Codable, CaseIterable, Hashable {
    case new
    case editing
    case toPost     = "to_post"
    case posting
    case production
    case archived

    public var label: String {
        switch self {
        case .new:        return "New"
        case .editing:    return "Editing"
        case .toPost:     return "To Post"
        case .posting:    return "Posting"
        case .production: return "Production"
        case .archived:   return "Archived"
        }
    }

    public var sortOrder: Int {
        switch self {
        case .new:        return 0
        case .editing:    return 1
        case .toPost:     return 2
        case .posting:    return 3
        case .production: return 4
        case .archived:   return 5
        }
    }

    public var systemImage: String {
        switch self {
        case .new:        return "doc.badge.plus"
        case .editing:    return "wand.and.stars"
        case .toPost:     return "paperplane"
        case .posting:    return "paperplane.circle.fill"
        case .production: return "checkmark.seal.fill"
        case .archived:   return "archivebox"
        }
    }
}

public struct Clip: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    public var id: String
    public var externalClipId: String?
    public var trackingTag: String?
    public var personaCode: String
    public var title: String
    public var descriptionRaw: String
    public var descriptionRefined: String
    public var keywords: String
    public var performers: String
    public var clipFilename: String?
    public var thumbnailFilename: String?
    public var previewFilename: String?
    public var lengthSeconds: Int?
    public var priceCents: Int?
    public var salesCount: Int
    public var incomeCents: Int
    public var contentDate: String?
    public var goLiveDate: String?
    public var fcpProjectFolder: String?
    public var productionFolder: String?
    public var status: String
    public var statusOverride: String?
    public var archived: Bool
    public var notes: String
    public var transcript: String

    public var mp4Md5: String
    public var mp4Sha1: String
    public var mp4Sha256: String
    public var mp4SizeBytes: Int64?
    public var reducedMd5: String
    public var reducedSha1: String
    public var reducedSha256: String
    public var reducedSizeBytes: Int64?
    public var hashesComputedAt: String

    public var postingExcluded: Bool
    public var exclusionReason: String
    public var exclusionNotes: String

    public var createdAt: String
    public var updatedAt: String

    public static let databaseTableName = "clips"

    enum CodingKeys: String, CodingKey {
        case id
        case externalClipId = "external_clip_id"
        case trackingTag = "tracking_tag"
        case personaCode = "persona_code"
        case title
        case descriptionRaw = "description_raw"
        case descriptionRefined = "description_refined"
        case keywords
        case performers
        case clipFilename = "clip_filename"
        case thumbnailFilename = "thumbnail_filename"
        case previewFilename = "preview_filename"
        case lengthSeconds = "length_seconds"
        case priceCents = "price_cents"
        case salesCount = "sales_count"
        case incomeCents = "income_cents"
        case contentDate = "content_date"
        case goLiveDate = "go_live_date"
        case fcpProjectFolder = "fcp_project_folder"
        case productionFolder = "production_folder"
        case status
        case statusOverride = "status_override"
        case archived
        case notes
        case transcript
        case mp4Md5            = "mp4_md5"
        case mp4Sha1           = "mp4_sha1"
        case mp4Sha256         = "mp4_sha256"
        case mp4SizeBytes      = "mp4_size_bytes"
        case reducedMd5        = "reduced_md5"
        case reducedSha1       = "reduced_sha1"
        case reducedSha256     = "reduced_sha256"
        case reducedSizeBytes  = "reduced_size_bytes"
        case hashesComputedAt  = "hashes_computed_at"
        case postingExcluded   = "posting_excluded"
        case exclusionReason   = "exclusion_reason"
        case exclusionNotes    = "exclusion_notes"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: String,
        externalClipId: String? = nil,
        trackingTag: String? = nil,
        personaCode: String,
        title: String,
        descriptionRaw: String,
        descriptionRefined: String,
        keywords: String,
        performers: String,
        clipFilename: String? = nil,
        thumbnailFilename: String? = nil,
        previewFilename: String? = nil,
        lengthSeconds: Int? = nil,
        priceCents: Int? = nil,
        salesCount: Int,
        incomeCents: Int,
        contentDate: String? = nil,
        goLiveDate: String? = nil,
        fcpProjectFolder: String? = nil,
        productionFolder: String? = nil,
        status: String,
        statusOverride: String? = nil,
        archived: Bool,
        notes: String,
        transcript: String,
        mp4Md5: String,
        mp4Sha1: String,
        mp4Sha256: String,
        mp4SizeBytes: Int64? = nil,
        reducedMd5: String,
        reducedSha1: String,
        reducedSha256: String,
        reducedSizeBytes: Int64? = nil,
        hashesComputedAt: String,
        postingExcluded: Bool,
        exclusionReason: String,
        exclusionNotes: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.externalClipId = externalClipId
        self.trackingTag = trackingTag
        self.personaCode = personaCode
        self.title = title
        self.descriptionRaw = descriptionRaw
        self.descriptionRefined = descriptionRefined
        self.keywords = keywords
        self.performers = performers
        self.clipFilename = clipFilename
        self.thumbnailFilename = thumbnailFilename
        self.previewFilename = previewFilename
        self.lengthSeconds = lengthSeconds
        self.priceCents = priceCents
        self.salesCount = salesCount
        self.incomeCents = incomeCents
        self.contentDate = contentDate
        self.goLiveDate = goLiveDate
        self.fcpProjectFolder = fcpProjectFolder
        self.productionFolder = productionFolder
        self.status = status
        self.statusOverride = statusOverride
        self.archived = archived
        self.notes = notes
        self.transcript = transcript
        self.mp4Md5 = mp4Md5
        self.mp4Sha1 = mp4Sha1
        self.mp4Sha256 = mp4Sha256
        self.mp4SizeBytes = mp4SizeBytes
        self.reducedMd5 = reducedMd5
        self.reducedSha1 = reducedSha1
        self.reducedSha256 = reducedSha256
        self.reducedSizeBytes = reducedSizeBytes
        self.hashesComputedAt = hashesComputedAt
        self.postingExcluded = postingExcluded
        self.exclusionReason = exclusionReason
        self.exclusionNotes = exclusionNotes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var statusEnum: ClipStatus {
        ClipStatus(rawValue: status) ?? .new
    }

    public var keywordList: [String] {
        keywords.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
