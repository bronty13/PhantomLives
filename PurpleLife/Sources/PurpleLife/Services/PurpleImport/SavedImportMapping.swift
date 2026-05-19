import Foundation

/// A named, persisted import mapping. Each lives in its own
/// encrypted file under `~/Library/Application Support/PurpleLife/mappings/`.
/// The user can save / re-run / edit / duplicate / export-share these.
///
/// The on-disk envelope mirrors the pattern `SchemaIO` uses for
/// schema files — `format` + `exportedAt` + payload — so a future
/// `purplelife.import-mapping.v2` shape can be introduced without
/// breaking the reader (forward-compat decode tries the envelope
/// first, then falls back to a bare payload).
struct SavedImportMapping: Codable, Identifiable, Hashable {

    /// Stable UUID, persisted as the filename stem.
    var id: String

    /// User-facing display label.
    var name: String

    var sourceFormat: PurpleImport.SourceFormat
    var sourceOptions: [String: SourceOptionValue]   // delimiter, encoding, root path, etc.

    /// Target type id. `nil` while the user is mid-wizard and hasn't
    /// chosen yet, or when `newTypeTemplate != nil` (the wizard
    /// resolves to a real type id at run-time and back-fills).
    var targetTypeId: String?
    var newTypeTemplate: NewTypeTemplate?

    var fieldMappings: [FieldMapping]
    var upsertStrategy: UpsertStrategy
    var keyFieldKey: String?       // required when upsertStrategy == .upsertOnKey

    var attachmentBasePath: AttachmentBasePath
    var attachmentMissingPolicy: AttachmentMissingPolicy

    var previewSampleSize: Int
    var createdAt: String          // ISO-8601
    var updatedAt: String          // ISO-8601

    // MARK: - Embedded shapes

    enum UpsertStrategy: String, Codable, Hashable {
        case insertOnly
        case upsertOnKey
    }

    /// How the runner resolves attachment values. `inline` covers the
    /// "JSON field carries base64 bytes" case (Phase 2+); `relative`
    /// and `absolute` cover local-file-path values.
    enum AttachmentBasePath: String, Codable, Hashable {
        case relative   // resolve against the import file's directory
        case absolute   // value is an absolute file URL
        case inline     // value is base64-encoded bytes
    }

    enum AttachmentMissingPolicy: String, Codable, Hashable {
        case skipField  // leave the attachment field empty, continue
        case failRow    // mark the row failed
    }

    /// One row in the field-mapping table. Maps a source locator
    /// (column name or path expression) to a target field key, plus
    /// per-mapping coercion + error policy.
    struct FieldMapping: Codable, Hashable, Identifiable {
        var id: String                         // UI-stable
        var source: PurpleImport.SourceLocator
        var targetKey: String
        var expectedKind: FieldKind
        var transforms: [Transform]
        var defaultValue: SourceOptionValue?   // applied when source is empty + onError == .fillDefault
        var onError: OnError
    }

    enum Transform: Codable, Hashable {
        case trim
        case lowercase
        case uppercase
        case regexReplace(pattern: String, replacement: String)
        case prefix(String)
        case suffix(String)

        enum CodingKeys: String, CodingKey { case kind, value, pattern, replacement }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .kind) {
            case "trim":         self = .trim
            case "lowercase":    self = .lowercase
            case "uppercase":    self = .uppercase
            case "regexReplace":
                self = .regexReplace(
                    pattern: try c.decode(String.self, forKey: .pattern),
                    replacement: try c.decode(String.self, forKey: .replacement)
                )
            case "prefix":       self = .prefix(try c.decode(String.self, forKey: .value))
            case "suffix":       self = .suffix(try c.decode(String.self, forKey: .value))
            default:             self = .trim
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .trim:        try c.encode("trim", forKey: .kind)
            case .lowercase:   try c.encode("lowercase", forKey: .kind)
            case .uppercase:   try c.encode("uppercase", forKey: .kind)
            case .regexReplace(let p, let r):
                try c.encode("regexReplace", forKey: .kind)
                try c.encode(p, forKey: .pattern)
                try c.encode(r, forKey: .replacement)
            case .prefix(let s): try c.encode("prefix", forKey: .kind); try c.encode(s, forKey: .value)
            case .suffix(let s): try c.encode("suffix", forKey: .kind); try c.encode(s, forKey: .value)
            }
        }
    }

    enum OnError: String, Codable, Hashable {
        case skipRow        // drop the row entirely
        case fillDefault    // substitute defaultValue (or empty when nil)
        case abort          // stop the import run
    }

    /// Inline mini-schema captured during the wizard's "Create new
    /// type from this source" path. The runner materializes it into
    /// a real `ObjectType` via the sink's `createType(_:)` before
    /// the first record write.
    struct NewTypeTemplate: Codable, Hashable {
        var name: String
        var pluralName: String
        var systemImage: String
        var colorHex: String
        var isVault: Bool
        var fields: [ProposedField]

        struct ProposedField: Codable, Hashable {
            var name: String
            var kind: FieldKind
            var required: Bool
            var options: [FieldOption]
        }
    }

    // MARK: - Defaults

    static func newDraft() -> SavedImportMapping {
        let now = ISO8601DateFormatter().string(from: Date())
        return SavedImportMapping(
            id: UUID().uuidString,
            name: "Untitled mapping",
            sourceFormat: .csv,
            sourceOptions: [:],
            targetTypeId: nil,
            newTypeTemplate: nil,
            fieldMappings: [],
            upsertStrategy: .insertOnly,
            keyFieldKey: nil,
            attachmentBasePath: .relative,
            attachmentMissingPolicy: .skipField,
            previewSampleSize: 10,
            createdAt: now,
            updatedAt: now
        )
    }
}

// MARK: - File envelope

/// Versioned envelope written to `~/Library/Application Support/PurpleLife/mappings/<uuid>.purplelifemapping.json`
/// and used by the import-from-file flow in `MappingStore`. Same
/// pattern as `SchemaIO.Envelope`.
struct SavedImportMappingEnvelope: Codable {
    static let formatIdentifier = "purplelife.import-mapping.v1"

    var format: String
    var exportedAt: String
    var mapping: SavedImportMapping

    init(_ mapping: SavedImportMapping) {
        self.format = Self.formatIdentifier
        self.exportedAt = ISO8601DateFormatter().string(from: Date())
        self.mapping = mapping
    }
}

// MARK: - Codable for option values

/// Codable wrapper for the small set of source-option value types we
/// need: string, bool, int. Keeps the source-options dict round-
/// trippable through Codable without dragging in AnyCodable's full
/// any-shape machinery.
enum SourceOptionValue: Codable, Hashable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)

    enum CodingKeys: String, CodingKey { case kind, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "string": self = .string(try c.decode(String.self, forKey: .value))
        case "bool":   self = .bool(try c.decode(Bool.self, forKey: .value))
        case "int":    self = .int(try c.decode(Int.self, forKey: .value))
        case "double": self = .double(try c.decode(Double.self, forKey: .value))
        default:       self = .string("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let s): try c.encode("string", forKey: .kind); try c.encode(s, forKey: .value)
        case .bool(let b):   try c.encode("bool",   forKey: .kind); try c.encode(b, forKey: .value)
        case .int(let i):    try c.encode("int",    forKey: .kind); try c.encode(i, forKey: .value)
        case .double(let d): try c.encode("double", forKey: .kind); try c.encode(d, forKey: .value)
        }
    }

    var rawAny: Any {
        switch self {
        case .string(let s): return s
        case .bool(let b):   return b
        case .int(let i):    return i
        case .double(let d): return d
        }
    }
}
