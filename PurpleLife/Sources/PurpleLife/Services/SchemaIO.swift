import Foundation

/// Pure-function JSON encode / decode for `ObjectType`. Mirrors
/// `ThemeIO` — the AppKit pickers live in the view layer so this stays
/// unit-testable.
///
/// File format is a small envelope:
/// ```
/// {
///   "format": "purplelife.schema.v1",
///   "exportedAt": "<iso8601>",
///   "types": [ <ObjectType>, ... ]
/// }
/// ```
/// The envelope (vs. a bare `[ObjectType]`) lets a future version add
/// fields (per-type variants, palette colors, etc.) without breaking
/// older importers — see how `format` is required on read for
/// forward-compat.
enum SchemaIO {

    /// Suggested file extension. Matches the `.purplelifetheme.json`
    /// pattern: the `.json` suffix means any JSON tool can open it; the
    /// `.purplelifeschema` segment is greppable and prepares the ground
    /// for a future UTType registration.
    static let fileExtension = "purplelifeschema.json"

    /// Default filename for a single-type export. Uses the type's plural
    /// name for readability — that's what the user sees in the sidebar.
    static func defaultFilename(for type: ObjectType) -> String {
        "\(sanitizedFilename(type.pluralName)).\(fileExtension)"
    }

    /// Default filename for a multi-type export.
    static func defaultFilenameForBundle(_ types: [ObjectType]) -> String {
        if types.count == 1 {
            return defaultFilename(for: types[0])
        }
        return "schemas-\(types.count).\(fileExtension)"
    }

    /// Sanitize a string into a filesystem-safe basename. Same rules as
    /// `ThemeIO.sanitizedFilename`.
    static func sanitizedFilename(_ s: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\u{0000}")
            .union(.controlCharacters)
        let cleaned = s
            .components(separatedBy: illegal)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return cleaned.isEmpty ? "schema" : cleaned
    }

    // MARK: - Envelope

    private static let formatTag = "purplelife.schema.v1"

    /// On-disk envelope. `format` is required to distinguish this file
    /// type from arbitrary JSON; mismatches throw a typed error so the
    /// importer can show a useful message.
    struct Envelope: Codable {
        var format: String
        var exportedAt: Date
        var types: [ObjectType]
    }

    /// Errors thrown by the import path.
    enum ImportError: LocalizedError {
        case unrecognizedFormat(String?)
        case empty

        var errorDescription: String? {
            switch self {
            case .unrecognizedFormat(let tag):
                return "Not a PurpleLife schema file (\(tag ?? "no format tag"))."
            case .empty:
                return "The file contained no schema types."
            }
        }
    }

    // MARK: - Encode / decode

    /// Encode one or more types into the envelope. Sorted keys + pretty
    /// printing for stable diffs.
    static func encode(_ types: [ObjectType]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let envelope = Envelope(format: formatTag, exportedAt: Date(), types: types)
        return try encoder.encode(envelope)
    }

    /// Decode an envelope. On read, every imported `ObjectType` gets a
    /// fresh `id` and every `FieldDef` inside gets a fresh `id` — same
    /// rationale as `ThemeIO.decode`: re-importing the same file (or
    /// sharing one across Macs) must never collide with an existing
    /// type, and the `key` on each field already encodes the identity
    /// for record data.
    ///
    /// `builtIn` is forced to `false` on import — built-ins ship with
    /// the app and are identified by stable ids that imports must not
    /// claim.
    static func decode(from data: Data) throws -> [ObjectType] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // We accept either the v1 envelope or a bare ObjectType array
        // for forward-compat with anyone hand-rolling a schema file.
        // The envelope path is the documented one.
        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            if let bare = try? decoder.decode([ObjectType].self, from: data) {
                envelope = Envelope(format: formatTag, exportedAt: Date(), types: bare)
            } else if let one = try? decoder.decode(ObjectType.self, from: data) {
                envelope = Envelope(format: formatTag, exportedAt: Date(), types: [one])
            } else {
                throw error
            }
        }

        guard envelope.format == formatTag else {
            throw ImportError.unrecognizedFormat(envelope.format)
        }
        guard !envelope.types.isEmpty else {
            throw ImportError.empty
        }

        return envelope.types.map(freshenIds)
    }

    /// Strips the source ids and stamps fresh ones — used both on
    /// disk-read and when materializing a `SchemaLibrary.Entry`. Forces
    /// `builtIn = false` because imports never claim built-in status.
    static func freshenIds(_ type: ObjectType) -> ObjectType {
        var fresh = type
        fresh.id = UUID().uuidString
        fresh.builtIn = false
        fresh.updatedAt = nil
        fresh.fields = fresh.fields.map { field in
            var f = field
            f.id = UUID().uuidString
            return f
        }
        return fresh
    }

    // MARK: - Disk helpers

    static func write(_ types: [ObjectType], to url: URL) throws {
        let data = try encode(types)
        try data.write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> [ObjectType] {
        let data = try Data(contentsOf: url)
        return try decode(from: data)
    }
}
