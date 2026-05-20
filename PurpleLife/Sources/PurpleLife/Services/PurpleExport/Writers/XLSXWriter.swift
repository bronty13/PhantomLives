import Foundation
import ZIPFoundation

/// Excel (.xlsx) writer — Phase 4.5. A minimal OOXML emitter packed
/// via ZIPFoundation. Round-trips through `XLSXReader`: the test
/// suite writes a fixture, opens it with CoreXLSX, and asserts the
/// header row + cells decode back to what we wrote.
///
/// Design choices:
///  • Inline strings (`t="inlineStr"`) for every text cell — no
///    sharedStrings.xml part. Slightly larger files but the emitter
///    stays stateless and one-pass.
///  • Native numbers and booleans use Excel's typed cell shapes
///    (`<v>` with no `t` for numbers, `t="b"` for booleans).
///  • Dates and date-times convert to Excel serial numbers (days
///    since 1899-12-30) and reference a `cellXfs` index whose
///    `numFmtId` is 14 (date) or 22 (date+time) — Excel and
///    `XLSXReader.detectDateStyleIndices` both recognise these built-in
///    formats without `numFmts` overrides.
///  • Header row uses a bold font style (cellXfs index 3). Light
///    presentational nicety; both Excel and Numbers honor it.
///  • Link / attachment / select / multiSelect / rating / URL /
///    email / rich-text / long-text fields use
///    `ExportService.renderCell` for the displayed value, matching
///    the CSV / Markdown / HTML / PDF writers. Identifies + hashes
///    resolve to human-readable labels rather than ids.
@MainActor
final class XLSXWriter: PurpleExportWriter {

    var format: PurpleExport.DestinationFormat { .xlsx }

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
        let sheetXML = buildSheetXML(
            type: type,
            fields: fields,
            selections: selections,
            records: records,
            linkResolver: linkResolver,
            attachmentResolver: attachmentResolver
        )
        let data = try packArchive(
            sheetName: sheetTabName(for: type),
            sheetXML: sheetXML
        )
        try data.write(to: destination, options: .atomic)
        return data.count
    }

    // MARK: - Worksheet XML

    /// Render the worksheet body: one header row (bold) followed by
    /// one data row per record. Cell payloads are typed where it
    /// matters (numbers, booleans, dates) and inline-string for
    /// everything else.
    private func buildSheetXML(
        type: SourceTypeInfo,
        fields: [SourceFieldInfo],
        selections: [PurpleExport.FieldSelection],
        records: [SourceRecord],
        linkResolver: (String) -> String?,
        attachmentResolver: (String) -> String?
    ) -> String {
        let fieldByKey = Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0) })

        // Column layout matches the CSVWriter / MarkdownWriter shape:
        // id, …user-chosen headers…, created_at, updated_at.
        let headers: [String] = ["id"] + selections.map(\.header) + ["created_at", "updated_at"]
        // Column-index → SourceFieldInfo (when the column corresponds
        // to a real schema field). Used to decide which Excel type
        // shape to emit for each cell.
        var columnFieldKey: [Int: String] = [:]
        for (i, sel) in selections.enumerated() {
            columnFieldKey[i + 1] = sel.fieldKey   // i+1 because index 0 is the id column
        }

        var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        xml += #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">"#
        xml += "<sheetData>"

        // Header row.
        xml += #"<row r="1">"#
        for (i, header) in headers.enumerated() {
            let ref = Self.columnLetter(for: i) + "1"
            xml += Self.inlineStringCell(ref: ref, text: header, styleIndex: 3)
        }
        xml += "</row>"

        // Data rows.
        for (rowIdx, record) in records.enumerated() {
            let excelRow = rowIdx + 2   // 1-based, after the header
            xml += #"<row r="\#(excelRow)">"#

            // id column
            xml += Self.inlineStringCell(
                ref: Self.columnLetter(for: 0) + String(excelRow),
                text: record.id,
                styleIndex: nil
            )

            // User-picked fields
            for (i, sel) in selections.enumerated() {
                let columnIndex = i + 1
                let ref = Self.columnLetter(for: columnIndex) + String(excelRow)
                let raw = record.fields[sel.fieldKey]
                let info = fieldByKey[sel.fieldKey]
                xml += renderCellXML(
                    ref: ref,
                    raw: raw,
                    kind: info?.kind ?? .text,
                    options: info?.options ?? [],
                    linkResolver: linkResolver,
                    attachmentResolver: attachmentResolver
                )
            }

            // created_at / updated_at as ISO strings (the
            // PurpleExportSource hands them in already formatted).
            let createdRef = Self.columnLetter(for: selections.count + 1) + String(excelRow)
            let updatedRef = Self.columnLetter(for: selections.count + 2) + String(excelRow)
            xml += Self.inlineStringCell(ref: createdRef, text: record.createdAt, styleIndex: nil)
            xml += Self.inlineStringCell(ref: updatedRef, text: record.updatedAt, styleIndex: nil)

            xml += "</row>"
        }

        xml += "</sheetData>"
        xml += "</worksheet>"
        return xml
    }

    /// Pick the Excel type shape per FieldKind. Numbers and booleans
    /// stay typed so a downstream `XLSXReader.preview` infers them as
    /// `.number` / `.boolean` rather than `.text`. Dates convert to
    /// Excel serials and reference a numFmt-bearing cellXfs index;
    /// the rest stringify through `ExportService.renderCell`.
    private func renderCellXML(
        ref: String,
        raw: Any?,
        kind: FieldKind,
        options: [FieldOption],
        linkResolver: (String) -> String?,
        attachmentResolver: (String) -> String?
    ) -> String {
        guard let raw, !(raw is NSNull) else {
            return Self.emptyCell(ref: ref)
        }
        switch kind {
        case .number:
            if let d = Self.numericValue(raw) {
                return Self.numericCell(ref: ref, value: d, styleIndex: nil)
            }
            return Self.emptyCell(ref: ref)

        case .boolean:
            if let b = Self.booleanValue(raw) {
                return Self.booleanCell(ref: ref, value: b)
            }
            return Self.emptyCell(ref: ref)

        case .rating:
            if let d = Self.numericValue(raw) {
                return Self.numericCell(ref: ref, value: d, styleIndex: nil)
            }
            return Self.emptyCell(ref: ref)

        case .date:
            if let serial = Self.excelSerial(from: raw) {
                return Self.numericCell(ref: ref, value: serial, styleIndex: 1)
            }
            // Couldn't parse as date — emit the rendered text so the
            // user at least sees the value.
            let s = ExportService.renderCell(
                raw, kind: kind, options: options,
                linkTitle: linkResolver, attachmentLabel: attachmentResolver
            )
            return Self.inlineStringCell(ref: ref, text: s, styleIndex: nil)

        case .dateTime:
            if let serial = Self.excelSerial(from: raw) {
                return Self.numericCell(ref: ref, value: serial, styleIndex: 2)
            }
            let s = ExportService.renderCell(
                raw, kind: kind, options: options,
                linkTitle: linkResolver, attachmentLabel: attachmentResolver
            )
            return Self.inlineStringCell(ref: ref, text: s, styleIndex: nil)

        default:
            let s = ExportService.renderCell(
                raw, kind: kind, options: options,
                linkTitle: linkResolver, attachmentLabel: attachmentResolver
            )
            return Self.inlineStringCell(ref: ref, text: s, styleIndex: nil)
        }
    }

    // MARK: - Cell encoding helpers

    private static func inlineStringCell(ref: String, text: String, styleIndex: Int?) -> String {
        let style = styleIndex.map { " s=\"\($0)\"" } ?? ""
        let escaped = xmlEscape(text)
        // <c r="A1" s="3" t="inlineStr"><is><t xml:space="preserve">…</t></is></c>
        return "<c r=\"\(ref)\"\(style) t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escaped)</t></is></c>"
    }

    private static func numericCell(ref: String, value: Double, styleIndex: Int?) -> String {
        let style = styleIndex.map { " s=\"\($0)\"" } ?? ""
        return "<c r=\"\(ref)\"\(style)><v>\(formatNumber(value))</v></c>"
    }

    private static func booleanCell(ref: String, value: Bool) -> String {
        return "<c r=\"\(ref)\" t=\"b\"><v>\(value ? 1 : 0)</v></c>"
    }

    private static func emptyCell(ref: String) -> String {
        return "<c r=\"\(ref)\"/>"
    }

    /// Render a Double without trailing zero noise. Excel parses any
    /// of these forms back to the same value.
    private static func formatNumber(_ d: Double) -> String {
        if d == d.rounded(), abs(d) < 1e15 {
            return String(Int64(d))
        }
        return String(d)
    }

    // MARK: - Value coercion

    private static func numericValue(_ raw: Any) -> Double? {
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        if let i = raw as? Int64 { return Double(i) }
        if let n = raw as? NSNumber { return n.doubleValue }
        if let s = raw as? String, let d = Double(s) { return d }
        return nil
    }

    private static func booleanValue(_ raw: Any) -> Bool? {
        if let b = raw as? Bool { return b }
        if let n = raw as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue }
        if let s = raw as? String {
            let lower = s.lowercased()
            if ["true", "yes", "1"].contains(lower) { return true }
            if ["false", "no", "0"].contains(lower) { return false }
        }
        if let i = raw as? Int { return i != 0 }
        return nil
    }

    /// Convert an ISO date / dateTime string (or a Date) into an
    /// Excel serial — days since 1899-12-30, fractional part being
    /// the time of day. Mirrors the inverse of
    /// `XLSXReader.isoStringFromExcelSerial(_:)`.
    private static func excelSerial(from raw: Any) -> Double? {
        let date: Date
        if let d = raw as? Date {
            date = d
        } else if let s = raw as? String {
            guard let parsed = parseDateString(s) else { return nil }
            date = parsed
        } else {
            return nil
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let epoch = cal.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 1899, month: 12, day: 30
        )) else { return nil }
        let secondsPerDay: Double = 86_400
        let delta = date.timeIntervalSince(epoch)
        return delta / secondsPerDay
    }

    /// Accept the two shapes our other writers / source emit:
    ///   • "yyyy-MM-dd"            — calendar day
    ///   • ISO-8601 with time      — full date-time
    /// Both interpreted in UTC so the round-trip back through
    /// `XLSXReader.isoStringFromExcelSerial` lands on the same day.
    private static func parseDateString(_ s: String) -> Date? {
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = TimeZone(identifier: "UTC")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        if let d = dayFormatter.date(from: s) { return d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: s)
    }

    // MARK: - Column letters

    /// Convert a 0-based column index to Excel's A/B/.../Z/AA/AB/...
    /// labelling. Matches the inverse used by `XLSXReader`.
    static func columnLetter(for index: Int) -> String {
        var n = index + 1
        var out = ""
        while n > 0 {
            let r = (n - 1) % 26
            out = String(UnicodeScalar(65 + r)!) + out
            n = (n - 1) / 26
        }
        return out
    }

    // MARK: - XML escaping

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
                    // Strip control characters except tab/newline/carriage-return —
                    // Excel rejects raw 0x00–0x08, 0x0B–0x0C, 0x0E–0x1F in cell text.
                    if v < 0x20, v != 0x09, v != 0x0A, v != 0x0D { continue }
                }
                out.append(c)
            }
        }
        return out
    }

    // MARK: - Sheet tab name

    /// Excel limits sheet names to 31 chars and forbids `\/?*[]:`.
    /// Empty names get a default. We lean on the type's plural name
    /// so a user sees "Books" on the tab rather than "Sheet1".
    private func sheetTabName(for type: SourceTypeInfo) -> String {
        let base = type.pluralName.isEmpty ? (type.name.isEmpty ? "Records" : type.name) : type.pluralName
        let forbidden: Set<Character> = ["\\", "/", "?", "*", "[", "]", ":"]
        var cleaned = base.filter { !forbidden.contains($0) }
        if cleaned.isEmpty { cleaned = "Records" }
        if cleaned.count > 31 { cleaned = String(cleaned.prefix(31)) }
        return cleaned
    }

    // MARK: - ZIP packing

    /// Assemble the OOXML parts into an in-memory ZIP archive. We use
    /// `.deflate` so files stay reasonable in size, and write through
    /// a memory-backed archive so the caller gets one Data they
    /// atomically write to disk.
    private func packArchive(sheetName: String, sheetXML: String) throws -> Data {
        let archive: Archive
        do {
            archive = try Archive(data: Data(), accessMode: .create)
        } catch {
            throw XLSXWriterError.archiveCreateFailed
        }

        let parts: [(path: String, body: String)] = [
            ("[Content_Types].xml",         Self.contentTypesXML()),
            ("_rels/.rels",                 Self.rootRelsXML()),
            ("xl/workbook.xml",             Self.workbookXML(sheetName: sheetName)),
            ("xl/_rels/workbook.xml.rels",  Self.workbookRelsXML()),
            ("xl/styles.xml",               Self.stylesXML()),
            ("xl/worksheets/sheet1.xml",    sheetXML)
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
            throw XLSXWriterError.archiveFinalizeFailed
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
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\
        </Types>
        """
    }

    private static func rootRelsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
        </Relationships>
        """
    }

    private static func workbookXML(sheetName: String) -> String {
        let safe = xmlEscape(sheetName)
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
        <sheets>\
        <sheet name="\(safe)" sheetId="1" r:id="rId1"/>\
        </sheets>\
        </workbook>
        """
    }

    private static func workbookRelsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>\
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
        </Relationships>
        """
    }

    /// cellXfs indices used by the writer:
    ///   0 — default (no style)
    ///   1 — date         (numFmtId 14, "m/d/yyyy")
    ///   2 — date+time    (numFmtId 22, "m/d/yyyy h:mm")
    ///   3 — header bold  (fontId 1)
    /// XLSXReader's `builtInDateFormatIDs` includes 14 and 22, so the
    /// round-trip path lights up `dateStyleIndices = {1, 2}` and
    /// decodes our serials back as ISO date strings.
    private static func stylesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
        <fonts count="2">\
        <font><sz val="11"/><name val="Calibri"/></font>\
        <font><b/><sz val="11"/><name val="Calibri"/></font>\
        </fonts>\
        <fills count="1"><fill><patternFill patternType="none"/></fill></fills>\
        <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
        <cellXfs count="4">\
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>\
        <xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
        <xf numFmtId="22" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
        <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>\
        </cellXfs>\
        </styleSheet>
        """
    }
}

// MARK: - Errors

enum XLSXWriterError: LocalizedError {
    case archiveCreateFailed
    case archiveFinalizeFailed

    var errorDescription: String? {
        switch self {
        case .archiveCreateFailed:    return "Couldn't initialise an in-memory ZIP archive for the .xlsx output."
        case .archiveFinalizeFailed:  return "Couldn't finalise the .xlsx ZIP archive."
        }
    }
}
