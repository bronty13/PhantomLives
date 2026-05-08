import Foundation
import GRDB

/// Workflow status for a clip. Transitions:
///   new       → user fills initial metadata (persona, title, description,
///               categories, go-live date)
///   editing   → post-production work in progress; capture fcp_project_folder,
///               production_folder, length_seconds
///   to_post   → editing complete, ready to be posted
///   posting   → at least one scoped site posted; not all yet
///   production → every site in the persona's scope is posted (final)
///   archived  → out of rotation
enum ClipStatus: String, Codable, CaseIterable, Hashable {
    case new
    case editing
    case toPost     = "to_post"
    case posting
    case production
    case archived

    var label: String {
        switch self {
        case .new:        return "New"
        case .editing:    return "Editing"
        case .toPost:     return "To Post"
        case .posting:    return "Posting"
        case .production: return "Production"
        case .archived:   return "Archived"
        }
    }

    /// Pipeline ordering — used for queue sorts and "next stage" hints.
    var sortOrder: Int {
        switch self {
        case .new:        return 0
        case .editing:    return 1
        case .toPost:     return 2
        case .posting:    return 3
        case .production: return 4
        case .archived:   return 5
        }
    }

    /// SF Symbol that fits the stage.
    var systemImage: String {
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

struct Clip: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    var id: String                              // "YYYY-MM-DD-#####" (display format)
    var externalClipId: String?
    var trackingTag: String?
    var personaCode: String
    var title: String
    var descriptionRaw: String
    var descriptionRefined: String
    var keywords: String                        // comma-joined
    var performers: String
    var clipFilename: String?
    var thumbnailFilename: String?
    var previewFilename: String?
    var lengthSeconds: Int?
    var priceCents: Int?
    var salesCount: Int
    var incomeCents: Int
    var contentDate: String?                    // "YYYY-MM-DD"
    var goLiveDate: String?
    var fcpProjectFolder: String?               // post-production: path to FCP project
    var productionFolder: String?               // post-production: path to render/output folder
    var status: String                          // ClipStatus.rawValue (auto-derived)
    var statusOverride: String?                 // when non-nil, pins status; bypasses computeStatus
    var archived: Bool
    var notes: String
    var transcript: String                      // whisper-generated; empty when not yet run

    // File-integrity hashes (empty string = not yet computed)
    var mp4Md5: String
    var mp4Sha1: String
    var mp4Sha256: String
    var mp4SizeBytes: Int64?
    var reducedMd5: String
    var reducedSha1: String
    var reducedSha256: String
    var reducedSizeBytes: Int64?
    var hashesComputedAt: String                // ISO timestamp; empty until first run

    /// Per-clip "do not post" flag. Excluded clips are filtered out of
    /// posting batches and the Posting Queue. Reason + notes are
    /// surfaced in the editor and the clip detail.
    var postingExcluded: Bool
    var exclusionReason: String                 // picked from exclusion_reasons.label
    var exclusionNotes: String

    var createdAt: String
    var updatedAt: String

    static let databaseTableName = "clips"

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

    var statusEnum: ClipStatus {
        ClipStatus(rawValue: status) ?? .new
    }

    var keywordList: [String] {
        keywords.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
