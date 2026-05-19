import Foundation

/// A named, persisted export configuration. Each lives in its own
/// encrypted file under `~/Library/Application Support/PurpleLife/export-configs/`.
/// Same persistence shape as `SavedImportMapping` (per-file + envelope
/// + EncryptedJSON.safeWrite); a malformed file can't poison the
/// rest of the list, and the file is independently shareable.
struct SavedExportConfig: Codable, Identifiable, Hashable {

    /// Stable UUID; persisted as the filename stem.
    var id: String

    /// User-facing label.
    var name: String

    /// The schema type to export from.
    var typeId: String?

    /// Which records of that type to include.
    var selector: PurpleExport.RecordSelector

    /// Field subset + per-field header rename. Empty array means
    /// "export all fields in schema order."
    var fields: [PurpleExport.FieldSelection]

    var format: PurpleExport.DestinationFormat
    var formatOptions: PurpleExport.FormatOptions
    var destination: PurpleExport.Destination

    var createdAt: String      // ISO-8601
    var updatedAt: String      // ISO-8601

    static func newDraft() -> SavedExportConfig {
        let now = ISO8601DateFormatter().string(from: Date())
        return SavedExportConfig(
            id: UUID().uuidString,
            name: "Untitled export",
            typeId: nil,
            selector: .all,
            fields: [],
            format: .csv,
            formatOptions: PurpleExport.FormatOptions(),
            destination: PurpleExport.Destination(),
            createdAt: now,
            updatedAt: now
        )
    }
}

// MARK: - File envelope

/// Same envelope shape `SchemaIO` and `SavedImportMappingEnvelope`
/// use: `format` + `exportedAt` + payload. Lets the decoder accept
/// the bare payload as a forward-compat fallback when older / newer
/// shapes appear in the wild.
struct SavedExportConfigEnvelope: Codable {
    static let formatIdentifier = "purplelife.export-config.v1"

    var format: String
    var exportedAt: String
    var config: SavedExportConfig

    init(_ config: SavedExportConfig) {
        self.format = Self.formatIdentifier
        self.exportedAt = ISO8601DateFormatter().string(from: Date())
        self.config = config
    }
}
