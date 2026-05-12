import Foundation

/// One entry in a `.noteLog` field — a single timestamped note in the
/// log, with optional file attachments. The body text is rich-text
/// formatted (same `{rtf, plain}` shape `FieldKind.richText` uses).
struct NoteLogEntry: Codable, Identifiable, Hashable {
    var id: String
    var createdAt: String          // ISO-8601
    var updatedAt: String          // ISO-8601 — bumped on edit
    var rtf: String                // base64 of RTF/RTFD bytes; "" when empty
    var plain: String              // mirror text for FTS + compact previews
    var attachments: [NoteLogAttachmentRef]

    static func new(rtf: Data, plain: String, attachments: [NoteLogAttachmentRef] = []) -> NoteLogEntry {
        let now = ISO8601DateFormatter().string(from: Date())
        return NoteLogEntry(
            id: UUID().uuidString,
            createdAt: now,
            updatedAt: now,
            rtf: rtf.base64EncodedString(),
            plain: plain,
            attachments: attachments
        )
    }

    var rtfData: Data {
        Data(base64Encoded: rtf) ?? Data()
    }
}

/// Denormalized attachment metadata stored inside a `NoteLogEntry`. The
/// row also lives in the `attachments` table — that's the source of
/// truth for the actual file. Storing filename/mimeType/sizeBytes
/// inline means the chip can render without a DB lookup per entry on
/// every redraw.
struct NoteLogAttachmentRef: Codable, Hashable, Identifiable {
    var id: String              // attachments table row id
    var sha256: String
    var filename: String
    var mimeType: String
    var sizeBytes: Int64
}

/// Storage shape for the whole `.noteLog` field value. Lives inside
/// `fields_json` keyed by the field's storage key.
struct NoteLogValue: Codable, Equatable {
    var entries: [NoteLogEntry]

    static let empty = NoteLogValue(entries: [])

    /// Construct a JSON-compatible dictionary for insertion into
    /// `fields_json`. Round-trips through `JSONEncoder` / `JSONSerialization`
    /// so the result is a real `[String: Any]` (not a `Codable`-encoded
    /// blob), which `ObjectRecord.make` / `update` already serializes
    /// correctly.
    var jsonDictionary: [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return ["entries": []]
        }
        return dict
    }

    static func from(jsonDictionary dict: [String: Any]) -> NoteLogValue {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let value = try? JSONDecoder().decode(NoteLogValue.self, from: data) else {
            return .empty
        }
        return value
    }
}

/// Size budget for an individual entry's RTF blob. The whole noteLog
/// field's JSON serialization still has to fit under the CloudKit
/// record cap (≈1 MB), so per-entry needs to be modest enough that
/// a reasonable log doesn't push the parent record over.
enum NoteLogLimits {
    /// Hard cap per entry's RTF blob. ~200 KB lets a user attach a
    /// modest screenshot inline if they want, and still allows ~4
    /// such entries in one log before the field gets close to the
    /// CloudKit budget.
    static let maxEntryRTFBytes = 200_000

    static func fits(_ rtf: Data) -> Bool {
        rtf.count <= maxEntryRTFBytes
    }
}
