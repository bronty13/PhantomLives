import Foundation
import GRDB

/// Tier 5 of the resilience design (HANDOFF 2026-05-15). Writes the user's
/// entire decrypted dataset as plaintext to a single user-pickable file.
/// The "I want to be able to read this in 30 years on hardware Apple
/// doesn't sell yet" escape hatch — every field meaning is described by
/// the schema embedded in the same file, every record carries decoded
/// (not encrypted) field values, every attachment is reachable as
/// plaintext bytes.
///
/// Two output shapes, picked by the caller per export:
///
/// - **`.zipWithSidecars`** — one ZIP containing `snapshot.json`,
///   `attachments/<sha256>.<ext>`, and a human-readable `README.txt`.
///   Attachments stay binary-clean; openable per-file after unzip.
///
/// - **`.singleJSON`** — one JSON file with attachment bytes inlined
///   as base64 under each attachment metadata entry. True single-file
///   portability (drop into 1Password, paste into a long-term notes app).
///
/// Vault inclusion is the caller's decision — pass a non-empty
/// `excludingTypeIds` to keep Vault records out. See `BackupSettingsTab`
/// for the unlock-or-continue UX that decides what to pass.
@MainActor
enum PlaintextSnapshotService {

    static let formatTag = "purplelife.snapshot.v1"

    /// Filename prefix used by `defaultFilename`. Greppable so a future
    /// "Recent snapshots" listing UI can scope to "our" snapshots
    /// without picking up unrelated zips a user drops in the same dir.
    static let filenamePrefix = "PurpleLife-plaintext-snapshot-"

    enum Format {
        case zipWithSidecars
        case singleJSON

        var fileExtension: String {
            switch self {
            case .zipWithSidecars: return "zip"
            case .singleJSON:      return "json"
            }
        }

        var menuLabel: String {
            switch self {
            case .zipWithSidecars: return "ZIP with attachments"
            case .singleJSON:      return "Single JSON (base64 attachments)"
            }
        }
    }

    enum SnapshotError: Error, LocalizedError {
        case zipFailed(status: Int32, stderr: String)
        case writeFailed(String)
        case noData

        var errorDescription: String? {
            switch self {
            case .zipFailed(let s, let err): return "zip exited \(s): \(err)"
            case .writeFailed(let m):        return m
            case .noData:                    return "Nothing to export."
            }
        }
    }

    /// Summary returned to the UI after a successful export.
    struct Result {
        let outputURL: URL
        let format: Format
        let recordCount: Int
        let attachmentCount: Int
        let typeCount: Int
        let bytesOnDisk: Int
    }

    // MARK: - Public entry

    /// Build the full snapshot and write it to `destination`. The caller
    /// is responsible for path stamping / save panel; this just writes
    /// where it's told. Returns a summary the UI can show.
    @discardableResult
    static func export(
        to destination: URL,
        format: Format,
        schema: SchemaRegistry,
        settings: AppSettings,
        excludingTypeIds: Set<String> = []
    ) throws -> Result {
        let envelope = try buildEnvelope(
            schema: schema,
            settings: settings,
            excludingTypeIds: excludingTypeIds,
            inlineAttachmentBytes: format == .singleJSON
        )
        guard !envelope.records.isEmpty || !envelope.schema.types.isEmpty else {
            throw SnapshotError.noData
        }

        switch format {
        case .singleJSON:
            return try writeSingleJSON(envelope: envelope, to: destination)
        case .zipWithSidecars:
            return try writeZIP(envelope: envelope, to: destination)
        }
    }

    /// Default filename for a save panel. Stamped to the second so the
    /// user can run multiple exports the same day without overwrites.
    static func defaultFilename(format: Format) -> String {
        "\(filenamePrefix)\(timestamp()).\(format.fileExtension)"
    }

    // MARK: - Envelope assembly

    /// Self-describing JSON envelope. The 30-year design point is that a
    /// future reader with nothing but this file should be able to
    /// reconstruct the user's data. Every field id referenced inside
    /// `records[].fields` has its definition in `schema.types[].fields`;
    /// every select / multi-select option id has its label there;
    /// every attachment sha256 has a sidecar (ZIP mode) or inline
    /// base64 (singleJSON mode).
    struct Envelope: Codable {
        let format: String
        let formatDescription: String
        let exportedAt: String
        let appVersion: String
        let appBuildNumber: String
        let counts: Counts
        let notes: [String]
        let schema: SchemaBlock
        let records: [RecordOut]

        struct Counts: Codable {
            let types: Int
            let records: Int
            let attachments: Int
        }

        struct SchemaBlock: Codable {
            let types: [ObjectType]
            let tags: [TagDef]
        }

        struct RecordOut: Codable {
            let id: String
            let typeId: String
            let parentId: String?
            let createdAt: String
            let updatedAt: String
            /// Raw field dictionary as decoded from `ObjectRecord.fieldsJSON`.
            /// Field ids/keys resolve via `schema.types[].fields`;
            /// select option ids via `fields[].options`; link ids point
            /// at other records in this same `records` array.
            let fields: AnyCodable
            let attachments: [AttachmentOut]
        }

        struct AttachmentOut: Codable {
            let id: String
            let fieldKey: String
            let sha256: String
            let filename: String
            let mimeType: String
            let sizeBytes: Int64
            let createdAt: String
            /// `nil` in ZIP mode (bytes live in the `attachments/` sidecar
            /// directory). Base64-encoded plaintext bytes in single-JSON
            /// mode. Always nil when decryption failed — the metadata is
            /// preserved so the user sees what's missing, but the bytes
            /// aren't faked.
            let bytesBase64: String?
            /// Populated when the on-disk file couldn't be read or
            /// decrypted. Lets the future-reader understand why the
            /// payload is missing instead of inferring corruption.
            let readError: String?
        }
    }

    /// Walks every record + attachment and packs them into an `Envelope`.
    /// `inlineAttachmentBytes` controls whether `bytesBase64` gets
    /// populated (singleJSON) or left nil for ZIP-mode sidecar writes.
    static func buildEnvelope(
        schema: SchemaRegistry,
        settings: AppSettings,
        excludingTypeIds: Set<String>,
        inlineAttachmentBytes: Bool
    ) throws -> Envelope {
        let allTypes = schema.types
        let includedTypes = allTypes.filter { !excludingTypeIds.contains($0.id) }
        let includedTypeIdSet = Set(includedTypes.map(\.id))

        let allRecords = try DatabaseService.shared.fetchAllObjects()
        let included = allRecords.filter { includedTypeIdSet.contains($0.typeId) }

        // Index attachments by parent so each record only resolves its
        // own. One SQL read avoids N round-trips.
        let allAttachments = try DatabaseService.shared.dbPool.read { db in
            try Attachment.fetchAll(db)
        }
        var byParent: [String: [Attachment]] = [:]
        for a in allAttachments {
            byParent[a.parentObjectId, default: []].append(a)
        }

        var recordOuts: [Envelope.RecordOut] = []
        recordOuts.reserveCapacity(included.count)
        var attachmentCount = 0
        for record in included {
            let fieldDict = record.fields()
            let atts = (byParent[record.id] ?? []).sorted { lhs, rhs in
                if lhs.fieldKey != rhs.fieldKey { return lhs.fieldKey < rhs.fieldKey }
                return lhs.createdAt < rhs.createdAt
            }
            attachmentCount += atts.count
            let attOuts = atts.map { att -> Envelope.AttachmentOut in
                var bytes: String? = nil
                var readError: String? = nil
                if inlineAttachmentBytes {
                    do {
                        if let data = try AttachmentService.read(sha256: att.sha256) {
                            bytes = data.base64EncodedString()
                        } else {
                            readError = "file missing on disk"
                        }
                    } catch {
                        readError = error.localizedDescription
                    }
                }
                return Envelope.AttachmentOut(
                    id: att.id,
                    fieldKey: att.fieldKey,
                    sha256: att.sha256,
                    filename: att.filename,
                    mimeType: att.mimeType,
                    sizeBytes: att.sizeBytes,
                    createdAt: att.createdAt,
                    bytesBase64: bytes,
                    readError: readError
                )
            }
            recordOuts.append(Envelope.RecordOut(
                id: record.id,
                typeId: record.typeId,
                parentId: record.parentId,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                fields: AnyCodable(fieldDict),
                attachments: attOuts
            ))
        }

        let notes: [String] = [
            "All field meanings are described by schema.types[].fields — match each record field key to its definition there.",
            "Select / multi-select values are option ids; the option label lives under schema.types[].fields[].options[].",
            "Link values are record ids — find the linked record in this same records[] array.",
            "Tag ids inside records[].fields._tags resolve to entries in schema.tags[].",
            "Rich-text values are { plain, rtf } dictionaries; the plain mirror is always present.",
            "Note-log values are { entries: [{ createdAt, plain, rtf, attachments }] } — newest-first when displayed in-app."
        ]

        return Envelope(
            format: formatTag,
            formatDescription:
                "PurpleLife plaintext snapshot. All user data, decrypted, with the schema needed to interpret it. Generated by PurpleLife — see https://github.com/bronty13/PhantomLives for the source.",
            exportedAt: isoNow(),
            appVersion: AppVersion.marketing,
            appBuildNumber: AppVersion.build,
            counts: Envelope.Counts(
                types: includedTypes.count,
                records: recordOuts.count,
                attachments: attachmentCount
            ),
            notes: notes,
            schema: Envelope.SchemaBlock(
                types: includedTypes,
                tags: settings.tagVocabulary
            ),
            records: recordOuts
        )
    }

    // MARK: - Writers

    private static func writeSingleJSON(envelope: Envelope, to destination: URL) throws -> Result {
        let data = try encode(envelope)
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw SnapshotError.writeFailed(error.localizedDescription)
        }
        return Result(
            outputURL: destination,
            format: .singleJSON,
            recordCount: envelope.counts.records,
            attachmentCount: envelope.counts.attachments,
            typeCount: envelope.counts.types,
            bytesOnDisk: data.count
        )
    }

    private static func writeZIP(envelope: Envelope, to destination: URL) throws -> Result {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("pl-snap-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let jsonData = try encode(envelope)
        try jsonData.write(to: staging.appendingPathComponent("snapshot.json"), options: .atomic)

        // attachments/<sha>.<ext> — write each unique sha once.
        // Decryption failures land in the manifest already (via the
        // envelope's per-attachment readError when in single-JSON mode);
        // ZIP mode logs and skips so one corrupt file doesn't abort.
        let attachmentsDir = staging.appendingPathComponent("attachments", isDirectory: true)
        try fm.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        var written: Set<String> = []
        for rec in envelope.records {
            for att in rec.attachments where !written.contains(att.sha256) {
                written.insert(att.sha256)
                let ext = (att.filename as NSString).pathExtension.lowercased()
                let name = ext.isEmpty ? att.sha256 : "\(att.sha256).\(ext)"
                let outURL = attachmentsDir.appendingPathComponent(name)
                do {
                    if let data = try AttachmentService.read(sha256: att.sha256) {
                        try data.write(to: outURL, options: .atomic)
                    }
                } catch {
                    NSLog("PurpleLife: snapshot attachment \(att.sha256) skipped — \(error.localizedDescription)")
                }
            }
        }

        let readme = makeReadme(envelope: envelope)
        try readme.data(using: .utf8)!.write(to: staging.appendingPathComponent("README.txt"), options: .atomic)

        let tempZip = fm.temporaryDirectory
            .appendingPathComponent("pl-snap-\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: tempZip) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.arguments = ["-rqX", tempZip.path, ".", "-x", "*.DS_Store"]
        proc.currentDirectoryURL = staging
        let stderrPipe = Pipe()
        proc.standardError = stderrPipe
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let err = String(data: stderrPipe.fileHandleForReading.availableData, encoding: .utf8) ?? ""
            throw SnapshotError.zipFailed(status: proc.terminationStatus, stderr: err)
        }

        let zipData = try Data(contentsOf: tempZip)
        do {
            try zipData.write(to: destination, options: .atomic)
        } catch {
            throw SnapshotError.writeFailed(error.localizedDescription)
        }
        return Result(
            outputURL: destination,
            format: .zipWithSidecars,
            recordCount: envelope.counts.records,
            attachmentCount: envelope.counts.attachments,
            typeCount: envelope.counts.types,
            bytesOnDisk: zipData.count
        )
    }

    // MARK: - Helpers

    private static func encode(_ envelope: Envelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(envelope)
        } catch {
            throw SnapshotError.writeFailed("encode failed — \(error.localizedDescription)")
        }
    }

    private static func makeReadme(envelope: Envelope) -> String {
        var lines: [String] = []
        lines.append("PurpleLife — plaintext snapshot")
        lines.append("================================")
        lines.append("")
        lines.append("Exported: \(envelope.exportedAt)")
        lines.append("App: PurpleLife \(envelope.appVersion) (build \(envelope.appBuildNumber))")
        lines.append("")
        lines.append("Counts:")
        lines.append("  - \(envelope.counts.types) type definition(s)")
        lines.append("  - \(envelope.counts.records) record(s)")
        lines.append("  - \(envelope.counts.attachments) attachment(s)")
        lines.append("")
        lines.append("Files in this archive:")
        lines.append("  - snapshot.json   The full dataset — schema + records + tag vocabulary.")
        lines.append("  - attachments/    One file per unique attachment, named <sha256>.<ext>.")
        lines.append("                    sha256 is computed over the plaintext bytes; cross-")
        lines.append("                    reference with the `sha256` field on each attachment")
        lines.append("                    entry inside snapshot.json's records[].attachments[].")
        lines.append("  - README.txt      This file.")
        lines.append("")
        lines.append("How to read snapshot.json:")
        for note in envelope.notes {
            lines.append("  - \(note)")
        }
        lines.append("")
        lines.append("Format tag: \(envelope.format)")
        lines.append("This file format is described by the formatDescription and notes")
        lines.append("fields inside snapshot.json. A future PurpleLife may add fields;")
        lines.append("readers should treat unknown fields as forward-compat noise and ignore them.")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }

    private static func isoNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }
}

// `AnyCodable` was moved to `Services/AnyCodable.swift` in Phase 1
// of Purple Import / Purple Export so the import-runner + mapping
// codec can reuse it. Behavior is identical; see that file for the
// Bool-vs-Int trap rationale.
