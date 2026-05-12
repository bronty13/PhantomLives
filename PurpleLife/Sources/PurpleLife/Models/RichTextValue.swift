import AppKit
import Foundation

/// Storage shape for a `.richText` field value, lifted in and out of the
/// `fields_json` blob keyed by the field's storage key. The on-the-wire
/// JSON is `{ "rtf": "<base64>", "plain": "<text mirror>" }`.
///
/// The `rtf` payload is RTFD when the attributed string contains
/// attachments (pasted screenshots / images travel here, inline, so they
/// inherit the same E2E encryption the rest of `fields_json` gets via
/// `CKRecord.encryptedValues`) and plain RTF otherwise. The `plain`
/// mirror is the NSAttributedString's string content — feeds FTS5
/// indexing and the list-row two-line previews.
struct RichTextValue: Equatable {
    var rtf: Data
    var plain: String

    static let empty = RichTextValue(rtf: Data(), plain: "")

    /// Construct a JSON-compatible dictionary for insertion into
    /// `fields_json`. `rtf` becomes a base64 string so the surrounding
    /// JSON blob stays valid UTF-8 (binary bytes inside a JSON string
    /// don't survive Codable encoders that strict-check UTF-8).
    var jsonDictionary: [String: Any] {
        ["rtf": rtf.base64EncodedString(), "plain": plain]
    }

    /// Decode the dictionary written by `jsonDictionary`. Tolerant of
    /// schema-shaped variations seen in older snapshots / partial writes
    /// — missing keys yield empty strings rather than throwing.
    static func from(jsonDictionary dict: [String: Any]) -> RichTextValue {
        let plain = (dict["plain"] as? String) ?? ""
        if let b64 = dict["rtf"] as? String,
           let data = Data(base64Encoded: b64) {
            return RichTextValue(rtf: data, plain: plain)
        }
        return RichTextValue(rtf: Data(), plain: plain)
    }

    /// Build a RichTextValue from an `NSAttributedString`. RTFD encoding
    /// when the string contains attachments, plain RTF otherwise — same
    /// branching as PurpleTracker's `RichTextEditor.toRTFData()`.
    /// `plain` is the unwrapped string content. The conversion is `nil`-
    /// safe when AppKit refuses the encode (returns `.empty`); the live
    /// editor uses its own path with attachment-filewrapper recovery, so
    /// this static helper is primarily for tests + non-AppKit callers.
    static func from(attributedString: NSAttributedString) -> RichTextValue {
        let plain = attributedString.string
        guard attributedString.length > 0 else {
            return RichTextValue(rtf: Data(), plain: plain)
        }
        let range = NSRange(location: 0, length: attributedString.length)
        var docType: NSAttributedString.DocumentType = .rtf
        var hasAttachments = false
        attributedString.enumerateAttribute(.attachment, in: range, options: []) { value, _, stop in
            if value != nil { hasAttachments = true; stop.pointee = true }
        }
        if hasAttachments { docType = .rtfd }
        let data = (try? attributedString.data(
            from: range,
            documentAttributes: [.documentType: docType]
        )) ?? Data()
        return RichTextValue(rtf: data, plain: plain)
    }
}

/// Size budget for a rich-text field. CloudKit caps a single `CKRecord`
/// at ~1 MB total and `encryptedValues` payload counts toward it; the
/// budget here gives an honest ceiling for the `rtf` blob alone before
/// the rest of the record's fields eat into it.
enum RichTextLimits {
    /// Soft cap: warn but allow the save. Useful for triggering "this is
    /// getting big" UX before the user hits the hard ceiling.
    static let warnBytes = 700_000

    /// Hard cap: refuse the save. Below the CloudKit 1 MB record limit
    /// with headroom for the other fields, the encrypted-values envelope
    /// overhead, and CloudKit's own framing.
    static let maxBlobBytes = 900_000

    static func fits(_ data: Data) -> Bool {
        data.count <= maxBlobBytes
    }

    static func shouldWarn(_ data: Data) -> Bool {
        data.count > warnBytes
    }
}
