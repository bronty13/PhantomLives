import Foundation
import ZIPFoundation

/// Word (.docx) writer — Phase 5, minimal OOXML emitter on
/// ZIPFoundation. Symmetric with the XLSX writer (Phase 4.5): we
/// hand-roll the OOXML package rather than pulling in a heavier
/// write-capable lib.
///
/// Output shape — one record per "section":
///   • Type header (`Heading 1` style, bold + larger): `<plural name>`.
///   • Per record: a heading run `Record <id>` followed by one
///     paragraph per field, formatted `**<Header>:** <value>`.
///   • Section break (blank paragraph) between records.
///
/// What's deliberately NOT emitted:
///   • Tables — they'd let the export round-trip more cleanly, but
///     until we ship the v1.5 table-extraction reader they'd be a
///     one-way street. Phase 7 unlocks both sides together.
///   • Custom styles (fonts, colors) — Word picks up the document's
///     default. Keeps the package minimum-viable: 4 parts vs 8+ once
///     a styles.xml is involved.
///
/// Round-trip contract: feeding the writer's output back through
/// `DOCXReader.extractText(from:)` yields a body string that contains
/// every field value verbatim. The integration test pins this.
@MainActor
final class DOCXWriter: PurpleExportWriter {

    var format: PurpleExport.DestinationFormat { .docx }

    private var options = PurpleExport.FormatOptions()

    func setOptions(_ options: PurpleExport.FormatOptions) {
        self.options = options
    }

    // MARK: - PurpleExportWriter

    func write(
        type: SourceTypeInfo,
        fields: [SourceFieldInfo],
        selections: [PurpleExport.FieldSelection],
        records: [SourceRecord],
        linkResolver: (String) -> String?,
        attachmentResolver: (String) -> String?,
        to destination: URL
    ) throws -> Int {
        let documentXML = buildDocumentXML(
            type: type,
            fields: fields,
            selections: selections,
            records: records,
            linkResolver: linkResolver,
            attachmentResolver: attachmentResolver
        )
        let data = try packArchive(documentXML: documentXML)
        try data.write(to: destination, options: .atomic)
        return data.count
    }

    // MARK: - Document XML

    /// Assemble `word/document.xml`. Body = a header for the type,
    /// then a stack of records. Each record is a heading paragraph
    /// followed by one paragraph per field.
    private func buildDocumentXML(
        type: SourceTypeInfo,
        fields: [SourceFieldInfo],
        selections: [PurpleExport.FieldSelection],
        records: [SourceRecord],
        linkResolver: (String) -> String?,
        attachmentResolver: (String) -> String?
    ) -> String {
        let fieldByKey = Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0) })

        var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        xml += #"<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">"#
        xml += "<w:body>"

        // Document heading: type's plural name (or name as fallback).
        let title = type.pluralName.isEmpty ? type.name : type.pluralName
        xml += Self.headingParagraph(title, size: 32)

        for record in records {
            // Per-record heading. Identified by id so the round-trip
            // reader can recover the boundary.
            xml += Self.headingParagraph("Record \(record.id)", size: 24)

            for sel in selections {
                let raw = record.fields[sel.fieldKey]
                let info = fieldByKey[sel.fieldKey]
                let rendered = ExportService.renderCell(
                    raw,
                    kind: info?.kind ?? .text,
                    options: info?.options ?? [],
                    linkTitle: linkResolver,
                    attachmentLabel: attachmentResolver
                )
                xml += Self.labelValueParagraph(label: sel.header, value: rendered)
            }

            // created_at / updated_at as the closing two paragraphs.
            xml += Self.labelValueParagraph(label: "created_at", value: record.createdAt)
            xml += Self.labelValueParagraph(label: "updated_at", value: record.updatedAt)

            // Blank paragraph separates records visually + cleanly
            // splits them when the round-trip reader concatenates
            // paragraphs.
            xml += "<w:p/>"
        }

        xml += "</w:body></w:document>"
        return xml
    }

    // MARK: - Paragraph helpers

    /// A heading-style paragraph: single bold run, larger font size
    /// (half-points; 32 = 16pt, 24 = 12pt). Word treats `<w:sz>` as
    /// half-points by spec.
    static func headingParagraph(_ text: String, size halfPoints: Int) -> String {
        let escaped = xmlEscape(text)
        return "<w:p><w:pPr><w:spacing w:before=\"240\" w:after=\"120\"/></w:pPr>" +
               "<w:r><w:rPr><w:b/><w:sz w:val=\"\(halfPoints)\"/></w:rPr>" +
               "<w:t xml:space=\"preserve\">\(escaped)</w:t></w:r></w:p>"
    }

    /// A `Field name: value` paragraph. Two runs: bold label + space-and-colon,
    /// then a normal run with the value. The `xml:space="preserve"`
    /// is required for the leading space between the colon and the
    /// value.
    static func labelValueParagraph(label: String, value: String) -> String {
        let labelText = xmlEscape("\(label): ")
        let valueText = xmlEscape(value)
        return "<w:p>" +
               "<w:r><w:rPr><w:b/></w:rPr><w:t xml:space=\"preserve\">\(labelText)</w:t></w:r>" +
               "<w:r><w:t xml:space=\"preserve\">\(valueText)</w:t></w:r>" +
               "</w:p>"
    }

    // MARK: - XML escaping

    /// Same conservative escape set as `XLSXWriter`: the five XML
    /// reserved chars plus a strip for forbidden C0 control bytes.
    static func xmlEscape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&":  out += "&amp;"
            case "<":  out += "&lt;"
            case ">":  out += "&gt;"
            case "\"": out += "&quot;"
            case "'":  out += "&apos;"
            default:
                let scalars = c.unicodeScalars
                if scalars.count == 1, let scalar = scalars.first {
                    let v = scalar.value
                    if v < 0x20, v != 0x09, v != 0x0A, v != 0x0D { continue }
                }
                out.append(c)
            }
        }
        return out
    }

    // MARK: - ZIP packing

    /// Pack the four parts of a minimal-viable .docx package:
    ///   • `[Content_Types].xml`
    ///   • `_rels/.rels`
    ///   • `word/document.xml`
    ///   • `word/_rels/document.xml.rels`
    /// Word and Pages both open this shape without complaint.
    private func packArchive(documentXML: String) throws -> Data {
        let archive: Archive
        do {
            archive = try Archive(data: Data(), accessMode: .create)
        } catch {
            throw DOCXWriterError.archiveCreateFailed
        }

        let parts: [(path: String, body: String)] = [
            ("[Content_Types].xml",            Self.contentTypesXML()),
            ("_rels/.rels",                    Self.rootRelsXML()),
            ("word/_rels/document.xml.rels",   Self.docRelsXML()),
            ("word/document.xml",              documentXML)
        ]

        for part in parts {
            let bytes = Data(part.body.utf8)
            try archive.addEntry(
                with: part.path,
                type: .file,
                uncompressedSize: Int64(bytes.count),
                compressionMethod: .deflate,
                provider: { position, size in
                    let start = Int(position)
                    let end = min(start + size, bytes.count)
                    return bytes.subdata(in: start..<end)
                }
            )
        }

        guard let data = archive.data else {
            throw DOCXWriterError.archiveFinalizeFailed
        }
        return data
    }

    // MARK: - Static OOXML parts

    private static func contentTypesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>\
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
        </Types>
        """
    }

    private static func rootRelsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\
        </Relationships>
        """
    }

    private static func docRelsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        </Relationships>
        """
    }
}

// MARK: - Errors

enum DOCXWriterError: LocalizedError {
    case archiveCreateFailed
    case archiveFinalizeFailed

    var errorDescription: String? {
        switch self {
        case .archiveCreateFailed:    return "Couldn't initialise an in-memory ZIP archive for the .docx output."
        case .archiveFinalizeFailed:  return "Couldn't finalise the .docx ZIP archive."
        }
    }
}
