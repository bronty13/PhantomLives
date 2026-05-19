import Foundation

/// Top-level facade and shared types for **Purple Import** — the
/// generic import engine that brings external data (CSV, JSON, XML,
/// Markdown, Excel, Word, PDF) into PurpleLife by mapping source
/// columns/paths to a target schema type's fields.
///
/// Design boundary (PhantomLives reuse): the engine inside this
/// folder should not import `SchemaRegistry`, `ObjectEngine`, or
/// `AttachmentService` directly. It talks only to the protocols
/// declared in `Protocols/`. The concrete sink that wires those
/// protocols to PurpleLife's stores lives in `Sinks/PurpleLifeSink.swift`.
/// A sibling PhantomLives app reuses Purple Import by writing its
/// own sink against its own record store.
///
/// File ext for saved mappings: `.purplelifemapping.json`. Envelope
/// format identifier: `purplelife.import-mapping.v1`. Mirror of the
/// pattern `SchemaIO` uses for schema files.
enum PurpleImport {

    /// The eight source formats Purple Import supports across v1
    /// phases. CSV + JSON land in Phase 1 (this commit); Markdown +
    /// XML in Phase 2; Excel in Phase 3; Word + PDF in Phase 5.
    enum SourceFormat: String, Codable, CaseIterable, Hashable {
        case csv
        case json
        case markdown
        case xml
        case xlsx
        case docx
        case pdf

        var displayName: String {
            switch self {
            case .csv:      return "CSV"
            case .json:     return "JSON"
            case .markdown: return "Markdown"
            case .xml:      return "XML"
            case .xlsx:     return "Excel (.xlsx)"
            case .docx:     return "Word (.docx)"
            case .pdf:      return "PDF"
            }
        }

        var defaultFileExtensions: [String] {
            switch self {
            case .csv:      return ["csv", "tsv"]
            case .json:     return ["json", "ndjson"]
            case .markdown: return ["md", "markdown"]
            case .xml:      return ["xml"]
            case .xlsx:     return ["xlsx", "xlsm"]
            case .docx:     return ["docx"]
            case .pdf:      return ["pdf"]
            }
        }

        var systemImage: String {
            switch self {
            case .csv:      return "tablecells"
            case .json:     return "curlybraces"
            case .markdown: return "doc.richtext"
            case .xml:      return "chevron.left.forwardslash.chevron.right"
            case .xlsx:     return "tablecells.fill"
            case .docx:     return "doc.text"
            case .pdf:      return "doc.text.image"
            }
        }
    }

    /// Whether a source file is naturally "row × column" (CSV, Excel,
    /// Markdown table) or "tree of objects" (JSON, XML, Word, PDF).
    /// Drives the wizard's field-mapping UI: tabular shows a column
    /// dropdown per target field; tree shows a path expression.
    enum SourceShape: Hashable {
        case tabular(columns: [String], inferredKinds: [String: FieldKind])
        case tree(rootPaths: [String])
        case document(richText: String)  // Word/PDF v1 single-record body
    }

    /// Where a single source value lives. Mirrors `SourceShape`:
    /// tabular sources reference a column name; tree sources
    /// reference a path expression evaluated against the parsed tree.
    enum SourceLocator: Codable, Hashable {
        case column(String)
        case path(String)

        enum CodingKeys: String, CodingKey { case kind, value }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .kind) {
            case "column": self = .column(try c.decode(String.self, forKey: .value))
            case "path":   self = .path(try c.decode(String.self, forKey: .value))
            default:       self = .column("")
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .column(let s): try c.encode("column", forKey: .kind); try c.encode(s, forKey: .value)
            case .path(let s):   try c.encode("path",   forKey: .kind); try c.encode(s, forKey: .value)
            }
        }

        var displayLabel: String {
            switch self {
            case .column(let s): return s
            case .path(let s):   return s
            }
        }
    }

    /// One row from a parsed source. Keyed by `SourceLocator`. For
    /// tabular sources every row carries the same set of column
    /// locators; for tree sources the locators are path expressions
    /// the reader evaluated.
    struct SourceRow {
        let cells: [SourceLocator: Any]
        let rowIndex: Int

        /// `nil` for "key absent"; otherwise the parsed value, which
        /// may itself be `NSNull` for an explicit null source.
        func cell(at locator: SourceLocator) -> Any? {
            cells[locator]
        }
    }

    /// A preview of the parsed source — the first N rows + the
    /// detected column or path list. Powers the wizard's preview
    /// step.
    struct SourcePreview {
        let shape: SourceShape
        let sampleRows: [SourceRow]
        let totalRows: Int?  // nil if the reader can't count without a full scan
    }

    /// The handle a reader is given. URL-based today; the wizard's
    /// paste step constructs a tempfile and hands its URL in.
    enum SourceInput {
        case url(URL)
        case data(Data, filenameHint: String?)
    }

    // MARK: - Run-time events streamed to the UI

    enum RunEvent {
        case willStart(totalRows: Int?)
        case row(index: Int, status: RowStatus)
        case finished(summary: RunSummary)
        case failed(message: String)

        enum RowStatus {
            case inserted
            case updated
            case skipped(reason: String)
            case failed(reason: String)
        }
    }

    struct RunSummary {
        var inserted: Int
        var updated: Int
        var skipped: Int
        var failed: Int
        var startedAt: Date
        var finishedAt: Date

        var total: Int { inserted + updated + skipped + failed }
        var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }
    }

    // MARK: - Threshold for bulk path

    /// Imports of this many rows or more use the sink's `bulkInsert`
    /// path: one undo entry, deferred sync push, one end-of-run FTS
    /// reindex. Below this, each row goes through `upsert` for
    /// per-row error reporting + immediate visibility. The number is
    /// a tuning knob; 25 is small enough that 10× CSV typo iterations
    /// stay individually undoable, large enough that "I just typed a
    /// 50-row CSV in TextEdit" still pays the optimization.
    static let bulkThreshold = 25
}
