import Foundation

/// XML writer. Emits a `<records>` root with one `<record>` per
/// source record; each `<record>` wraps one element per selected
/// field whose tag is the user-chosen header, whose text content is
/// the rendered cell value. Round-trips through `XMLReader.read`
/// (with `rootPath: "$.records.record"`) for a write-then-read
/// sanity check.
///
/// Root + record element names are configurable via
/// `FormatOptions.xmlRootElement` / `xmlRecordElement` — the
/// defaults are `"records"` / `"record"`, but a user exporting
/// "Books" might set them to `"books"` / `"book"` for cosmetic
/// reasons.
@MainActor
final class XMLWriter: PurpleExportWriter {

    var format: PurpleExport.DestinationFormat { .xml }

    private var options = PurpleExport.FormatOptions()

    func setOptions(_ options: PurpleExport.FormatOptions) {
        self.options = options
    }

    func write(
        type: SourceTypeInfo,
        fields: [SourceFieldInfo],
        selections: [PurpleExport.FieldSelection],
        records: [SourceRecord],
        linkResolver: (String) -> String?,
        attachmentResolver: (String) -> String?,
        to destination: URL
    ) throws -> Int {
        let fieldByKey = Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0) })
        let rootName = sanitizeElementName(options.xmlRootElement, fallback: "records")
        let recordName = sanitizeElementName(options.xmlRecordElement, fallback: "record")

        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<\(rootName) type=\"\(escapeAttr(type.id))\" name=\"\(escapeAttr(type.name))\">\n"
        for record in records {
            out += "  <\(recordName) id=\"\(escapeAttr(record.id))\""
            out += " created_at=\"\(escapeAttr(record.createdAt))\""
            out += " updated_at=\"\(escapeAttr(record.updatedAt))\">\n"
            for sel in selections {
                let raw = record.fields[sel.fieldKey]
                let info = fieldByKey[sel.fieldKey]
                let value = ExportService.renderCell(
                    raw,
                    kind: info?.kind ?? .text,
                    options: info?.options ?? [],
                    linkTitle: linkResolver,
                    attachmentLabel: attachmentResolver
                )
                let tag = sanitizeElementName(sel.header, fallback: "field")
                out += "    <\(tag)>\(escapeText(value))</\(tag)>\n"
            }
            out += "  </\(recordName)>\n"
        }
        out += "</\(rootName)>\n"

        let data = out.data(using: .utf8) ?? Data()
        try data.write(to: destination, options: .atomic)
        return data.count
    }

    /// XML element names must start with a letter/underscore and
    /// contain only letters/digits/underscores/hyphens/periods. We
    /// slugify user-supplied headers to satisfy that, falling back
    /// to a default when nothing usable remains.
    private func sanitizeElementName(_ s: String, fallback: String) -> String {
        var out = ""
        var first = true
        for c in s {
            let allowed: Bool
            if first {
                allowed = c.isLetter || c == "_"
            } else {
                allowed = c.isLetter || c.isNumber || c == "_" || c == "-" || c == "."
            }
            if allowed {
                out.append(c)
                first = false
            } else if !out.isEmpty {
                out.append("_")
            }
        }
        return out.isEmpty ? fallback : out
    }

    private func escapeText(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeAttr(_ s: String) -> String {
        escapeText(s)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
