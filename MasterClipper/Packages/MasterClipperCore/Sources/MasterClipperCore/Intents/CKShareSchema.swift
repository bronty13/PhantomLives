import Foundation

/// Shared constants for the CloudKit shared-zone data model. Both the macOS
/// writer (ShareManager) and the iOS reader (SharedZoneReader) reference these
/// strings — keep them in sync by never typing the literals elsewhere.
public enum CKShareSchema {

    // MARK: - Record types

    /// One per shared clip. A projection of `clips` with only the fields a
    /// recipient needs to view / edit. The full `Clip` row's hashes,
    /// file-system paths, and other internal columns are not included.
    public static let sharedClipRecordType = "SharedClip"

    /// One per share. Carries metadata about the share itself (expiry,
    /// permission, label). Sits in the same zone as the SharedClip records.
    public static let shareMetadataRecordType = "ShareMetadata"

    /// One per recipient edit. Carries a JSON-encoded `IntentEnvelope` in
    /// the `envelopeJson` field. The macOS owner polls for these, applies
    /// them via `DatabaseService.apply(intent:)`, deletes on success.
    /// Reuses the entire Phase 4 intent infrastructure — only the transport
    /// is different (CKRecord vs iCloud Drive file).
    public static let sharedClipEditRecordType = "SharedClipEdit"

    /// CKShare's per-zone CKRecordZoneID name is `share-<uuid>`.
    public static let zoneNamePrefix = "share-"

    public static func zoneName(forShareId id: UUID) -> String {
        zoneNamePrefix + id.uuidString.lowercased()
    }

    /// Recover the share id from a zone name. Returns nil if the zone name
    /// doesn't follow our convention.
    public static func shareId(fromZoneName name: String) -> UUID? {
        guard name.hasPrefix(zoneNamePrefix) else { return nil }
        let suffix = String(name.dropFirst(zoneNamePrefix.count))
        return UUID(uuidString: suffix)
    }

    // MARK: - SharedClip field keys

    public enum SharedClipField {
        public static let clipId             = "clipId"
        public static let title              = "title"
        public static let descriptionRefined = "descriptionRefined"
        public static let descriptionRaw     = "descriptionRaw"
        public static let keywords           = "keywords"
        public static let performers         = "performers"
        public static let personaCode        = "personaCode"
        public static let status             = "status"
        public static let statusOverride     = "statusOverride"
        public static let archived           = "archived"
        public static let postingExcluded    = "postingExcluded"
        public static let exclusionReason    = "exclusionReason"
        public static let exclusionNotes     = "exclusionNotes"
        public static let goLiveDate         = "goLiveDate"
        public static let contentDate        = "contentDate"
        public static let lengthSeconds      = "lengthSeconds"
        public static let priceCents         = "priceCents"
        public static let salesCount         = "salesCount"
        public static let incomeCents        = "incomeCents"

        /// JSON-encoded `[ClipPosting]` so a single record carries the full
        /// posting state without N CK fetches per clip.
        public static let postingsJson       = "postingsJson"

        /// JSON-encoded `[ClipNote]`.
        public static let notesJson          = "notesJson"

        /// Mirrored from the snapshot's thumbnails folder so the recipient
        /// can render previews without filesystem access.
        public static let thumbnail          = "thumbnail"      // CKAsset

        /// Same value as ShareMetadata.expiresAt; duplicated on each record
        /// so the iOS reader can locally enforce expiry even before fetching
        /// the metadata record.
        public static let expiresAt          = "expiresAt"
    }

    // MARK: - SharedClipEdit field keys

    public enum SharedClipEditField {
        /// JSON of `IntentEnvelope`. macOS decodes and applies.
        public static let envelopeJson = "envelopeJson"
        /// Mirror of the envelope's `id` so it can be queried without parsing
        /// the JSON. Also used as the CKRecord's recordName so duplicate
        /// submissions collapse.
        public static let intentId = "intentId"
        /// Mirror of `clipId` for filtered fetches.
        public static let clipId = "clipId"
        /// Mirror of `createdAt` for sort + idempotency cross-check.
        public static let createdAt = "createdAt"
    }

    // MARK: - ShareMetadata field keys

    public enum ShareMetadataField {
        public static let expiresAt   = "expiresAt"   // Date
        public static let permission  = "permission"  // SharePermission.rawValue
        public static let label       = "label"       // String, optional
        public static let createdAt   = "createdAt"   // Date
        public static let revoked     = "revoked"     // Int (0/1)
        public static let createdByDeviceId = "createdByDeviceId"
        /// Cached count of SharedClip records in this zone, written at
        /// create time so the UI doesn't need a separate (CKQuery-based,
        /// schema-fragile) count fetch.
        public static let clipCount   = "clipCount"   // Int
    }

    /// The singleton record name under each shared zone for the metadata
    /// record. Predictable so iOS can fetch it without enumerating.
    public static let shareMetadataRecordName = "metadata"
}

/// What a recipient can do with a shared zone.
public enum SharePermission: String, Codable, Hashable, CaseIterable {
    case readOnly  = "read_only"
    case readWrite = "read_write"

    public var label: String {
        switch self {
        case .readOnly:  return "View only"
        case .readWrite: return "View + edit"
        }
    }
}

/// Recipient-facing snapshot of one shared share. Decoded from the
/// ShareMetadata record on iOS; the iOS Shared tab uses this to render
/// header info and gate edit affordances.
public struct ShareMetadata: Codable, Hashable, Identifiable {
    public let id: UUID
    public let label: String?
    public let permission: SharePermission
    public let expiresAt: Date
    public let createdAt: Date
    public let createdByDeviceId: String
    public let revoked: Bool

    public init(
        id: UUID,
        label: String?,
        permission: SharePermission,
        expiresAt: Date,
        createdAt: Date,
        createdByDeviceId: String,
        revoked: Bool
    ) {
        self.id = id
        self.label = label
        self.permission = permission
        self.expiresAt = expiresAt
        self.createdAt = createdAt
        self.createdByDeviceId = createdByDeviceId
        self.revoked = revoked
    }

    public var isExpired: Bool { Date() >= expiresAt }
}
