import Foundation
import AppKit

@MainActor
enum ExportService {

    // MARK: - CSV

    static func exportCSV(clips: [Clip], appState: AppState) -> String {
        let header = [
            "id","external_clip_id","persona","title","status",
            "content_date","go_live_date","length","price",
            "categories","keywords","performers","notes"
        ]
        var lines = [header.map { $0.csvEscaped }.joined(separator: ",")]
        for clip in clips {
            let cats = categoryNames(forClip: clip.id, appState: appState).joined(separator: ", ")
            let row: [String] = [
                clip.id,
                clip.externalClipId ?? "",
                clip.personaCode,
                clip.title,
                clip.statusEnum.label,
                clip.contentDate ?? "",
                clip.goLiveDate ?? "",
                DurationFormatter.format(clip.lengthSeconds),
                clip.priceCents.map { String(format: "%.2f", Double($0) / 100) } ?? "",
                cats,
                clip.keywords,
                clip.performers,
                clip.notes.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces),
            ]
            lines.append(row.map { $0.csvEscaped }.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Markdown

    static func exportMarkdown(clips: [Clip], appState: AppState) -> String {
        var md = "# MasterClipper export\n\n"
        md += "_\(clips.count) clips · exported \(isoNow())_\n\n"
        md += "| ID | Persona | Title | Status | Length | Go-Live | Categories |\n"
        md += "|---|---|---|---|---|---|---|\n"
        for c in clips {
            let cats = categoryNames(forClip: c.id, appState: appState).joined(separator: ", ")
            md += "| `\(c.id)` | \(c.personaCode) | \(c.title.replacingOccurrences(of: "|", with: "\\|")) | "
                + "\(c.statusEnum.label) | \(DurationFormatter.format(c.lengthSeconds)) | "
                + "\(c.goLiveDate ?? "—") | \(cats) |\n"
        }
        return md
    }

    static func exportClipMarkdown(_ clip: Clip, appState: AppState) -> String {
        let cats = categoryNames(forClip: clip.id, appState: appState).joined(separator: ", ")
        let postings = (try? DatabaseService.shared.fetchPostings(forClip: clip.id)) ?? []
        var md = "# \(clip.title.isEmpty ? "Untitled" : clip.title)\n\n"
        md += "- **Clip ID:** `\(clip.id)`\n"
        if let ext = clip.externalClipId, !ext.isEmpty { md += "- **External Clip ID:** \(ext)\n" }
        md += "- **Persona:** \(clip.personaCode)\n"
        md += "- **Status:** \(clip.statusEnum.label)\n"
        md += "- **Length:** \(DurationFormatter.format(clip.lengthSeconds))\n"
        if let cd = clip.contentDate, !cd.isEmpty { md += "- **Content date:** \(cd)\n" }
        if let gl = clip.goLiveDate,  !gl.isEmpty { md += "- **Go-Live date:** \(gl)\n" }
        if let cents = clip.priceCents { md += String(format: "- **Price:** $%.2f\n", Double(cents) / 100) }
        if !cats.isEmpty             { md += "- **Categories:** \(cats)\n" }
        if !clip.keywords.isEmpty    { md += "- **Keywords:** \(clip.keywords)\n" }
        if !clip.performers.isEmpty  { md += "- **Performers:** \(clip.performers)\n" }
        md += "\n## Description (raw)\n\n\(clip.descriptionRaw.isEmpty ? "_(empty)_" : clip.descriptionRaw)\n\n"
        md += "## Description (refined)\n\n\(clip.descriptionRefined.isEmpty ? "_(empty)_" : clip.descriptionRefined)\n\n"

        if !postings.isEmpty {
            md += "## Postings\n\n"
            for posting in postings {
                let site = appState.sites.first(where: { $0.id == posting.siteId })?.displayName ?? "site #\(posting.siteId)"
                let when = posting.postedDate ?? "(not posted)"
                md += "- **\(site):** \(posting.statusEnum.rawValue) (\(when))\n"
            }
            md += "\n"
        }

        if !clip.notes.isEmpty {
            md += "## Notes\n\n\(clip.notes)\n"
        }
        return md
    }

    static func exportClipPlainText(_ clip: Clip, appState: AppState) -> String {
        let cats = categoryNames(forClip: clip.id, appState: appState).joined(separator: ", ")
        var s = ""
        s += "[\(clip.id)] \(clip.title.isEmpty ? "Untitled" : clip.title) — \(clip.personaCode)\n"
        s += "Length: \(DurationFormatter.format(clip.lengthSeconds))"
        if let cents = clip.priceCents { s += String(format: "  ·  Price: $%.2f", Double(cents) / 100) }
        if let gl = clip.goLiveDate, !gl.isEmpty { s += "  ·  Go-Live: \(gl)" }
        s += "\n"
        if !cats.isEmpty { s += "Categories: \(cats)\n" }
        if !clip.keywords.isEmpty { s += "Keywords: \(clip.keywords)\n" }
        s += "\n"
        let body = clip.descriptionRefined.isEmpty ? clip.descriptionRaw : clip.descriptionRefined
        if !body.isEmpty {
            s += body
            s += "\n"
        }
        return s
    }

    // MARK: - XLSX

    static func exportXLSX(clips: [Clip], appState: AppState) -> Data? {
        var rows: [[String]] = [[
            "Clip ID","External Clip ID","Persona","Title","Status",
            "Content Date","Go-Live Date","Length (seconds)","Price (USD)",
            "Categories","Keywords","Performers","Description (raw)","Description (refined)","Notes"
        ]]
        for c in clips {
            let cats = categoryNames(forClip: c.id, appState: appState).joined(separator: ", ")
            rows.append([
                c.id,
                c.externalClipId ?? "",
                c.personaCode,
                c.title,
                c.statusEnum.label,
                c.contentDate ?? "",
                c.goLiveDate ?? "",
                c.lengthSeconds.map(String.init) ?? "",
                c.priceCents.map { String(format: "%.2f", Double($0) / 100) } ?? "",
                cats,
                c.keywords,
                c.performers,
                c.descriptionRaw,
                c.descriptionRefined,
                c.notes
            ])
        }
        return buildXLSX(sheetName: "Clips", rows: rows)
    }

    private static func buildXLSX(sheetName: String, rows: [[String]]) -> Data? {
        var sheetRows = ""
        for (ri, row) in rows.enumerated() {
            sheetRows += "<row r=\"\(ri + 1)\">"
            for (ci, cell) in row.enumerated() {
                let col = xlsxCol(ci)
                sheetRows += "<c r=\"\(col)\(ri + 1)\" t=\"inlineStr\"><is><t>\(xmlEscape(cell))</t></is></c>"
            }
            sheetRows += "</row>"
        }
        let sheetXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>\(sheetRows)</sheetData>
        </worksheet>
        """
        let workbookXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
                  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="\(xmlEscape(sheetName))" sheetId="1" r:id="rId1"/></sheets>
        </workbook>
        """
        let wbRelsXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        </Relationships>
        """
        let contentTypesXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        </Types>
        """
        let dotRelsXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """

        return zipOOXML(parts: [
            ("[Content_Types].xml", contentTypesXML),
            ("_rels/.rels", dotRelsXML),
            ("xl/workbook.xml", workbookXML),
            ("xl/_rels/workbook.xml.rels", wbRelsXML),
            ("xl/worksheets/sheet1.xml", sheetXML),
        ], extension: "xlsx")
    }

    // MARK: - DOCX

    static func exportDOCX(clips: [Clip], appState: AppState) -> Data? {
        func row(_ cells: [String], bold: Bool = false) -> String {
            let bold_ = bold ? "<w:rPr><w:b/></w:rPr>" : ""
            let tds = cells.map { "<w:tc><w:p><w:r>\(bold_)<w:t>\(xmlEscape($0))</w:t></w:r></w:p></w:tc>" }.joined()
            return "<w:tr>\(tds)</w:tr>"
        }
        var tableRows = row(["ID","Persona","Title","Status","Length","Go-Live","Categories"], bold: true)
        for c in clips {
            let cats = categoryNames(forClip: c.id, appState: appState).joined(separator: ", ")
            tableRows += row([
                c.id, c.personaCode, c.title, c.statusEnum.label,
                DurationFormatter.format(c.lengthSeconds), c.goLiveDate ?? "—", cats
            ])
        }
        let docXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>
        <w:p><w:r><w:rPr><w:b/><w:sz w:val="32"/></w:rPr><w:t>MasterClipper export</w:t></w:r></w:p>
        <w:p><w:r><w:t>\(clips.count) clips · exported \(xmlEscape(isoNow()))</w:t></w:r></w:p>
        <w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/></w:tblPr>\(tableRows)</w:tbl>
        </w:body></w:document>
        """
        let contentTypesXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """
        let dotRelsXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
        return zipOOXML(parts: [
            ("[Content_Types].xml", contentTypesXML),
            ("_rels/.rels", dotRelsXML),
            ("word/document.xml", docXML),
        ], extension: "docx")
    }

    // MARK: - PDF (full + per-clip)

    static func exportPDFReport(clips: [Clip], appState: AppState) -> Data {
        let pageW: CGFloat = 612
        let pageH: CGFloat = 792
        let margin: CGFloat = 50
        let pdf = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: CGSize(width: pageW, height: pageH))

        guard let consumer = CGDataConsumer(data: pdf as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return Data() }

        var fromTop: CGFloat = margin

        func beginPage() {
            ctx.beginPDFPage(nil)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            fromTop = margin
        }
        func ensureRoom(_ h: CGFloat) {
            if fromTop + h > pageH - margin {
                ctx.endPDFPage()
                beginPage()
            }
        }
        func draw(_ s: String, x: CGFloat, lineH: CGFloat, bold: Bool = false) {
            let font = bold ? NSFont.boldSystemFont(ofSize: lineH * 0.75)
                            : NSFont.systemFont(ofSize: lineH * 0.75)
            NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor.black])
                .draw(at: CGPoint(x: x, y: pageH - fromTop - lineH + lineH * 0.25))
        }
        func line(_ s: String, lineH: CGFloat, bold: Bool = false, indent: CGFloat = 0) {
            ensureRoom(lineH)
            draw(s, x: margin + indent, lineH: lineH, bold: bold)
            fromTop += lineH
        }

        beginPage()
        line("MasterClipper export", lineH: 26, bold: true)
        line("\(clips.count) clips · exported \(isoNow())", lineH: 13)
        fromTop += 8

        let colWidths: [CGFloat] = [120, 50, 200, 80, 60]
        let headers = ["Clip ID","Persona","Title","Status","Length"]
        ensureRoom(14)
        for (i, h) in headers.enumerated() {
            draw(h, x: margin + colWidths[..<i].reduce(0, +), lineH: 12, bold: true)
        }
        fromTop += 14

        for c in clips {
            ensureRoom(12)
            let cells = [
                c.id, c.personaCode,
                c.title.count > 35 ? String(c.title.prefix(34)) + "…" : c.title,
                c.statusEnum.label, DurationFormatter.format(c.lengthSeconds)
            ]
            for (i, cell) in cells.enumerated() {
                draw(cell, x: margin + colWidths[..<i].reduce(0, +), lineH: 11)
            }
            fromTop += 12
        }

        ctx.endPDFPage()
        ctx.closePDF()
        return pdf as Data
    }

    static func exportClipPDF(_ clip: Clip, appState: AppState) -> Data {
        let pageW: CGFloat = 612
        let pageH: CGFloat = 792
        let margin: CGFloat = 50
        let pdf = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: CGSize(width: pageW, height: pageH))
        guard let consumer = CGDataConsumer(data: pdf as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return Data() }

        var fromTop: CGFloat = margin
        func beginPage() {
            ctx.beginPDFPage(nil)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            fromTop = margin
        }
        func ensureRoom(_ h: CGFloat) {
            if fromTop + h > pageH - margin { ctx.endPDFPage(); beginPage() }
        }
        func draw(_ s: String, x: CGFloat, lineH: CGFloat, bold: Bool = false, color: NSColor = .black) {
            let font = bold ? NSFont.boldSystemFont(ofSize: lineH * 0.75)
                            : NSFont.systemFont(ofSize: lineH * 0.75)
            NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
                .draw(at: CGPoint(x: x, y: pageH - fromTop - lineH + lineH * 0.25))
        }
        func line(_ s: String, lineH: CGFloat, bold: Bool = false, indent: CGFloat = 0, color: NSColor = .black) {
            ensureRoom(lineH); draw(s, x: margin + indent, lineH: lineH, bold: bold, color: color); fromTop += lineH
        }
        func paragraph(_ text: String, lineH: CGFloat) {
            // Naive wrap at ~85 chars
            let raw = text.replacingOccurrences(of: "\r\n", with: "\n")
            for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
                let s = String(rawLine)
                var remainder = s
                while !remainder.isEmpty {
                    let chunk = String(remainder.prefix(85))
                    line(chunk, lineH: lineH)
                    remainder = String(remainder.dropFirst(chunk.count))
                }
                fromTop += 2
            }
        }

        beginPage()
        line(clip.title.isEmpty ? "Untitled clip" : clip.title, lineH: 24, bold: true)
        line("\(clip.personaCode) · \(clip.id) · \(clip.statusEnum.label)", lineH: 13, color: .secondaryLabelColor)
        fromTop += 6

        let cats = categoryNames(forClip: clip.id, appState: appState).joined(separator: ", ")
        let pairs: [(String, String)] = [
            ("External Clip ID", clip.externalClipId ?? "—"),
            ("Length",           DurationFormatter.format(clip.lengthSeconds)),
            ("Content date",     clip.contentDate ?? "—"),
            ("Go-Live date",     clip.goLiveDate ?? "—"),
            ("Price",            clip.priceCents.map { String(format: "$%.2f", Double($0) / 100) } ?? "—"),
            ("Categories",       cats.isEmpty ? "—" : cats),
            ("Keywords",         clip.keywords.isEmpty ? "—" : clip.keywords),
            ("Performers",       clip.performers.isEmpty ? "—" : clip.performers),
        ]
        for (k, v) in pairs {
            line("\(k):  \(v)", lineH: 12, indent: 0)
        }
        fromTop += 10

        line("Description (raw)", lineH: 14, bold: true); fromTop += 2
        paragraph(clip.descriptionRaw.isEmpty ? "(empty)" : clip.descriptionRaw, lineH: 12)
        fromTop += 6
        line("Description (refined)", lineH: 14, bold: true); fromTop += 2
        paragraph(clip.descriptionRefined.isEmpty ? "(empty)" : clip.descriptionRefined, lineH: 12)
        fromTop += 6

        if !clip.notes.isEmpty {
            line("Notes", lineH: 14, bold: true); fromTop += 2
            paragraph(clip.notes, lineH: 11)
        }

        ctx.endPDFPage()
        ctx.closePDF()
        return pdf as Data
    }

    // MARK: - Helpers

    private static func categoryNames(forClip id: String, appState: AppState) -> [String] {
        let ids = (try? DatabaseService.shared.categoryIds(forClip: id)) ?? []
        return ids.compactMap { cid in appState.categories.first(where: { $0.id == cid })?.name }
    }

    static func zipOOXML(parts: [(String, String)], extension ext: String) -> Data? {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("mc-export-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            for (relPath, content) in parts {
                let url = tmp.appendingPathComponent(relPath)
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.data(using: .utf8)!.write(to: url)
            }
            let zipURL = fm.temporaryDirectory.appendingPathComponent("mc-\(UUID().uuidString).\(ext)")
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            proc.arguments = ["-rqX", zipURL.path, "."]
            proc.currentDirectoryURL = tmp
            try proc.run()
            proc.waitUntilExit()
            let data = try Data(contentsOf: zipURL)
            try? fm.removeItem(at: tmp)
            try? fm.removeItem(at: zipURL)
            return data
        } catch {
            try? fm.removeItem(at: tmp)
            return nil
        }
    }

    static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func xlsxCol(_ index: Int) -> String {
        var n = index
        var result = ""
        repeat {
            result = String(UnicodeScalar(65 + (n % 26))!) + result
            n = n / 26 - 1
        } while n >= 0
        return result
    }

    static func isoNow() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: Date())
    }
}

private extension String {
    var csvEscaped: String {
        if contains(",") || contains("\"") || contains("\n") {
            return "\"" + replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return self
    }
}
