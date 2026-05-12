import Foundation

/// A clip received through a CKShare. Mirrors the subset of `Clip` fields
/// that the macOS publisher writes into a `SharedClip` CKRecord (see
/// `CKShareSchema.SharedClipField`). The iOS Shared tab and edit flow
/// operate on these, never on `Clip` directly.
public struct SharedClipRow: Identifiable, Hashable {
    public let id: String                 // clipId
    public let title: String
    public let descriptionRefined: String
    public let descriptionRaw: String
    public let keywords: String
    public let performers: String
    public let personaCode: String
    public let status: String
    public let statusOverride: String?
    public let archived: Bool
    public let postingExcluded: Bool
    public let exclusionReason: String
    public let exclusionNotes: String
    public let goLiveDate: String?
    public let contentDate: String?
    public let lengthSeconds: Int?
    public let priceCents: Int?
    public let salesCount: Int
    public let incomeCents: Int
    public let postings: [ClipPosting]
    public let notes: [ClipNote]
    public let thumbnailLocalURL: URL?    // local cache, populated after CKAsset download
    public let expiresAt: Date

    public init(
        id: String, title: String, descriptionRefined: String, descriptionRaw: String,
        keywords: String, performers: String, personaCode: String, status: String,
        statusOverride: String?, archived: Bool, postingExcluded: Bool,
        exclusionReason: String, exclusionNotes: String,
        goLiveDate: String?, contentDate: String?, lengthSeconds: Int?,
        priceCents: Int?, salesCount: Int, incomeCents: Int,
        postings: [ClipPosting], notes: [ClipNote],
        thumbnailLocalURL: URL?, expiresAt: Date
    ) {
        self.id = id
        self.title = title
        self.descriptionRefined = descriptionRefined
        self.descriptionRaw = descriptionRaw
        self.keywords = keywords
        self.performers = performers
        self.personaCode = personaCode
        self.status = status
        self.statusOverride = statusOverride
        self.archived = archived
        self.postingExcluded = postingExcluded
        self.exclusionReason = exclusionReason
        self.exclusionNotes = exclusionNotes
        self.goLiveDate = goLiveDate
        self.contentDate = contentDate
        self.lengthSeconds = lengthSeconds
        self.priceCents = priceCents
        self.salesCount = salesCount
        self.incomeCents = incomeCents
        self.postings = postings
        self.notes = notes
        self.thumbnailLocalURL = thumbnailLocalURL
        self.expiresAt = expiresAt
    }

    public var statusEnum: ClipStatus { ClipStatus(rawValue: status) ?? .new }
    public var isExpired: Bool { Date() >= expiresAt }
}

/// One accepted CKShare, including its metadata + the clip records visible
/// inside it.
public struct SharedShareSession: Identifiable, Hashable {
    public let id: UUID
    public let metadata: ShareMetadata
    public let clips: [SharedClipRow]
    public let ownerName: String?       // Mac owner's display name (best-effort)

    public init(id: UUID, metadata: ShareMetadata, clips: [SharedClipRow], ownerName: String? = nil) {
        self.id = id
        self.metadata = metadata
        self.clips = clips
        self.ownerName = ownerName
    }

    public var isExpired: Bool { metadata.isExpired }
    public var canEdit: Bool { metadata.permission == .readWrite && !metadata.isExpired && !metadata.revoked }
}
