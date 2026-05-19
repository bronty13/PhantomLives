import Foundation

/// Top-level facade and shared types for **Purple Export** — the
/// symmetric counterpart of Purple Import. Pulls records out of
/// PurpleLife (or any sibling app that conforms `PurpleExportSource`)
/// and writes them through a chosen format writer (CSV / JSON / XML /
/// Markdown / HTML / PDF in Phase 4; XLSX in Phase 4.5; DOCX in
/// Phase 5).
///
/// Design boundary mirrors Purple Import: engine code in this
/// folder talks to the host app only through `PurpleExportSource`,
/// never directly to `SchemaRegistry` / `ObjectEngine`. The concrete
/// adapter is `Sources/PurpleLifeSource.swift`. The protocol +
/// writers + runner + wizard are app-agnostic so a future
/// PhantomLives sibling can adopt by writing its own source.
///
/// File format identifier for saved configs:
/// `purplelife.export-config.v1`. File ext: `.purpleexport.json`.
enum PurpleExport {

    /// The seven destination formats Phase 4 supports end-to-end.
    /// XLSX writer ships in Phase 4.5 (read-only CoreXLSX needs a
    /// minimal OOXML emitter on top); DOCX ships with Phase 5 (Word
    /// reader/writer batch). Both are still in this enum so the
    /// wizard UI can grey-flag them.
    enum DestinationFormat: String, Codable, CaseIterable, Hashable {
        case csv
        case json
        case markdown
        case xml
        case html
        case pdf
        case xlsx
        case docx

        var displayName: String {
            switch self {
            case .csv:      return "CSV"
            case .json:     return "JSON"
            case .markdown: return "Markdown"
            case .xml:      return "XML"
            case .html:     return "HTML"
            case .pdf:      return "PDF"
            case .xlsx:     return "Excel (.xlsx)"
            case .docx:     return "Word (.docx)"
            }
        }

        var fileExtension: String {
            switch self {
            case .csv:      return "csv"
            case .json:     return "json"
            case .markdown: return "md"
            case .xml:      return "xml"
            case .html:     return "html"
            case .pdf:      return "pdf"
            case .xlsx:     return "xlsx"
            case .docx:     return "docx"
            }
        }

        var systemImage: String {
            switch self {
            case .csv:      return "tablecells"
            case .json:     return "curlybraces"
            case .markdown: return "doc.richtext"
            case .xml:      return "chevron.left.forwardslash.chevron.right"
            case .html:     return "doc.text"
            case .pdf:      return "doc.text.image"
            case .xlsx:     return "tablecells.fill"
            case .docx:     return "doc.text"
            }
        }
    }

    /// How the runner picks which records to export. Phase 4
    /// supports `.all`; the filter form is staged for Phase 4.5
    /// alongside the saved-search integration.
    enum RecordSelector: Codable, Hashable {
        case all
        /// SearchFilter id reference (resolved against the user's
        /// saved searches at run time). Empty for now; surfaced in
        /// the wizard's PickRecords step as "Use a saved search →
        /// <name>".
        case savedSearch(id: String)

        enum CodingKeys: String, CodingKey { case kind, value }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .kind) {
            case "all": self = .all
            case "savedSearch": self = .savedSearch(id: try c.decode(String.self, forKey: .value))
            default: self = .all
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .all: try c.encode("all", forKey: .kind)
            case .savedSearch(let id):
                try c.encode("savedSearch", forKey: .kind)
                try c.encode(id, forKey: .value)
            }
        }
    }

    /// One field in the export: target field key + optional header
    /// override (the column / property name the export uses).
    struct FieldSelection: Codable, Hashable, Identifiable {
        var id: String           // UUID for SwiftUI list stability
        var fieldKey: String     // source field key on the type
        var header: String       // user-facing column / property name
    }

    /// Per-format knobs. The wizard surfaces only the relevant
    /// subset for the chosen `DestinationFormat`.
    struct FormatOptions: Codable, Hashable {
        // CSV
        var csvDelimiter: String = ","
        var csvQuoteAlways: Bool = false
        // JSON
        var jsonShape: JSONShape = .arrayOfObjects
        var jsonPrettyPrint: Bool = true
        // Markdown
        var markdownShape: MarkdownShape = .table
        // XML
        var xmlRootElement: String = "records"
        var xmlRecordElement: String = "record"

        enum JSONShape: String, Codable, Hashable {
            case arrayOfObjects   // [{…}, {…}]
            case ndjson           // one object per line
            case nested           // { "type": …, "records": [{…}] }
        }

        enum MarkdownShape: String, Codable, Hashable {
            case table            // GFM pipe table (round-trips through MarkdownReader)
            case listPerRecord    // ## Title \n - key: value
        }
    }

    /// Where the file lands and how it's named.
    struct Destination: Codable, Hashable {
        enum Mode: String, Codable, Hashable {
            case `default`        // ~/Downloads/PurpleLife/
            case custom           // user-supplied path
        }
        var mode: Mode = .default
        var customPath: String?   // when mode == .custom
        /// Filename template. Tokens: {type-plural}, {type-name},
        /// {stamp} (YYYY-MM-DD-HHmmss), {ext}. Default produces
        /// "<type-plural>-<stamp>.<ext>" — matches the convention
        /// `ExportService.export(...)` already uses.
        var filenameTemplate: String = "{type-plural}-{stamp}.{ext}"
    }

    // MARK: - Run-time events streamed to the UI

    enum RunEvent {
        case willStart(totalRecords: Int)
        case wroteFile(at: URL, bytes: Int)
        case finished(summary: RunSummary)
        case failed(message: String)
    }

    struct RunSummary {
        var recordCount: Int
        var fileURL: URL
        var bytesOnDisk: Int
        var format: DestinationFormat
        var startedAt: Date
        var finishedAt: Date

        var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }
    }
}
