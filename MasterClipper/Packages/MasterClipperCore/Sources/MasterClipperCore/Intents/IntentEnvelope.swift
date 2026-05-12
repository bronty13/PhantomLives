import Foundation

/// A change request originated by the iOS app, persisted as a JSON file in
/// iCloud Drive (`intents/pending/<uuid>.json`). The macOS app polls the
/// folder, applies each intent into its live SQLite database, and moves the
/// file to `intents/applied/<uuid>.json` (or `conflicts/` if conflict
/// detection trips).
///
/// `baseSnapshotGeneratedAt` is the `manifest.generated_at` the iPhone read
/// before composing this intent. macOS compares it to `clips.updated_at` for
/// last-writer-wins conflict detection — the iPhone's clock isn't trusted.
public struct IntentEnvelope: Codable, Hashable, Identifiable {
    public let id: UUID
    public let kind: IntentKind
    public let clipId: String
    public let payload: IntentPayload
    public let createdAt: Date
    public let deviceId: String
    public let baseSnapshotGeneratedAt: String
    public let appVersion: String

    public init(
        id: UUID = UUID(),
        kind: IntentKind,
        clipId: String,
        payload: IntentPayload,
        createdAt: Date = Date(),
        deviceId: String,
        baseSnapshotGeneratedAt: String,
        appVersion: String
    ) {
        self.id = id
        self.kind = kind
        self.clipId = clipId
        self.payload = payload
        self.createdAt = createdAt
        self.deviceId = deviceId
        self.baseSnapshotGeneratedAt = baseSnapshotGeneratedAt
        self.appVersion = appVersion
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case clipId                    = "clip_id"
        case payload
        case createdAt                 = "created_at"
        case deviceId                  = "device_id"
        case baseSnapshotGeneratedAt   = "base_snapshot_generated_at"
        case appVersion                = "app_version"
    }
}

public enum IntentKind: String, Codable, Hashable, CaseIterable {
    case markPosted              = "mark_posted"
    case unmarkPosted            = "unmark_posted"
    case addNote                 = "add_note"
    case setStatus               = "set_status"
    case togglePostingExcluded   = "toggle_posting_excluded"
}

/// Type-safe payload union. Each case carries the fields the corresponding
/// `IntentKind` needs. JSON serialisation uses a `kind` tag — but since the
/// outer envelope already carries `kind`, we encode payloads with their own
/// `_kind` discriminator so the JSON file is self-describing for debugging.
public enum IntentPayload: Codable, Hashable {
    case markPosted(siteCode: String, postedDate: String)
    case unmarkPosted(siteCode: String)
    case addNote(body: String, operatorName: String)
    case setStatus(status: String?)        // nil = clear override
    case togglePostingExcluded(excluded: Bool, reason: String, notes: String)

    private enum Discriminator: String, Codable {
        case markPosted              = "mark_posted"
        case unmarkPosted            = "unmark_posted"
        case addNote                 = "add_note"
        case setStatus               = "set_status"
        case togglePostingExcluded   = "toggle_posting_excluded"
    }

    private enum CodingKeys: String, CodingKey {
        case kind         = "_kind"
        case siteCode     = "site_code"
        case postedDate   = "posted_date"
        case body
        case operatorName = "operator_name"
        case status
        case excluded
        case reason
        case notes
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .markPosted(let siteCode, let postedDate):
            try c.encode(Discriminator.markPosted, forKey: .kind)
            try c.encode(siteCode, forKey: .siteCode)
            try c.encode(postedDate, forKey: .postedDate)
        case .unmarkPosted(let siteCode):
            try c.encode(Discriminator.unmarkPosted, forKey: .kind)
            try c.encode(siteCode, forKey: .siteCode)
        case .addNote(let body, let operatorName):
            try c.encode(Discriminator.addNote, forKey: .kind)
            try c.encode(body, forKey: .body)
            try c.encode(operatorName, forKey: .operatorName)
        case .setStatus(let status):
            try c.encode(Discriminator.setStatus, forKey: .kind)
            try c.encodeIfPresent(status, forKey: .status)
        case .togglePostingExcluded(let excluded, let reason, let notes):
            try c.encode(Discriminator.togglePostingExcluded, forKey: .kind)
            try c.encode(excluded, forKey: .excluded)
            try c.encode(reason, forKey: .reason)
            try c.encode(notes, forKey: .notes)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Discriminator.self, forKey: .kind)
        switch kind {
        case .markPosted:
            self = .markPosted(
                siteCode: try c.decode(String.self, forKey: .siteCode),
                postedDate: try c.decode(String.self, forKey: .postedDate)
            )
        case .unmarkPosted:
            self = .unmarkPosted(siteCode: try c.decode(String.self, forKey: .siteCode))
        case .addNote:
            self = .addNote(
                body: try c.decode(String.self, forKey: .body),
                operatorName: try c.decode(String.self, forKey: .operatorName)
            )
        case .setStatus:
            self = .setStatus(status: try c.decodeIfPresent(String.self, forKey: .status))
        case .togglePostingExcluded:
            self = .togglePostingExcluded(
                excluded: try c.decode(Bool.self, forKey: .excluded),
                reason:   try c.decode(String.self, forKey: .reason),
                notes:    try c.decode(String.self, forKey: .notes)
            )
        }
    }
}

/// Folder layout under the iCloud ubiquity container. Mirrors SnapshotLayout's
/// approach so iOS writer + macOS reader can't drift on naming.
public enum IntentLayout {
    public static let intentsDir   = "intents"
    public static let pendingDir   = "pending"
    public static let appliedDir   = "applied"
    public static let conflictsDir = "conflicts"

    /// `intents/pending` relative to the ubiquity container's `Documents/`.
    public static func pendingDirURL(in ubiquityContainer: URL) -> URL {
        ubiquityContainer
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(intentsDir, isDirectory: true)
            .appendingPathComponent(pendingDir, isDirectory: true)
    }

    public static func appliedDirURL(in ubiquityContainer: URL) -> URL {
        ubiquityContainer
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(intentsDir, isDirectory: true)
            .appendingPathComponent(appliedDir, isDirectory: true)
    }

    public static func conflictsDirURL(in ubiquityContainer: URL) -> URL {
        ubiquityContainer
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(intentsDir, isDirectory: true)
            .appendingPathComponent(conflictsDir, isDirectory: true)
    }
}
