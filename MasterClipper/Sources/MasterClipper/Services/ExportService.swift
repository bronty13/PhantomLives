import Foundation
import AppKit
import MasterClipperCore

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

    /// Plain-text "Information Needed" block for a single clip, mirroring the
    /// Reports → Information Needed → Copy for creator payload. Shows Blank /
    /// None Defined for missing fields; only includes the go-live line when
    /// it's actually missing.
    static func plainTextInformationNeeded(_ clip: Clip, appState: AppState) -> String {
        let cats = categoryNames(forClip: clip.id, appState: appState)
        let descMissing = clip.descriptionRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let catsMissing = cats.isEmpty
        let goLiveMissing = (clip.goLiveDate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let title = clip.title.isEmpty ? "Untitled" : clip.title
        var lines: [String] = ["Please confirm/provide the following:", ""]
        lines.append("\(clip.id) - \(title) [\(clip.personaCode)]")
        lines.append("Description: \(descMissing ? "Blank" : clip.descriptionRaw)")
        lines.append("Categories: \(catsMissing ? "None Defined" : cats.joined(separator: ", "))")
        if goLiveMissing {
            lines.append("Go-live date: Not set")
        }
        return lines.joined(separator: "\n")
    }

    /// Plain-text "Verification" block for a single clip. Always emits all
    /// fields — including ones we already have — so the creator can read the
    /// whole record back. Uses the refined description (falling back to raw
    /// when refined is blank but raw isn't).
    static func plainTextVerification(_ clip: Clip, appState: AppState) -> String {
        let cats = categoryNames(forClip: clip.id, appState: appState)
        let title = clip.title.isEmpty ? "Untitled" : clip.title

        let refined = clip.descriptionRefined.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = clip.descriptionRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let descValue: String = {
            if !refined.isEmpty { return clip.descriptionRefined }
            if !raw.isEmpty     { return clip.descriptionRaw }
            return "Not Set"
        }()

        let goLive = (clip.goLiveDate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        lines.append("\(clip.id) - \(title) [\(clip.personaCode)] - \(clip.statusEnum.label)")
        lines.append("Description: \(descValue)")
        lines.append("Categories: \(cats.isEmpty ? "Not Set" : cats.joined(separator: ", "))")
        lines.append("Go-live date: \(goLive.isEmpty ? "Not Set" : goLive)")
        return lines.joined(separator: "\n")
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

    // MARK: - Weekly report

    /// Markdown for the weekly rollup. Sections for last / this / next week +
    /// the not-in-production list. Tables use github-flavoured pipes so it
    /// renders nicely in iMessage / Notion / GitHub previews.
    static func exportWeeklyMarkdown(rollup: ReportService.WeeklyRollup, appState: AppState) -> String {
        var md = "# Weekly Report\n\n"
        md += "_Anchor week: \(formatRange(rollup.thisWeekRange)) · exported \(isoNow())_\n\n"
        md += weeklyMarkdownSection(title: "Last week",
                                    subtitle: "Items that went live last week",
                                    range: rollup.lastWeekRange,
                                    items: rollup.lastWeek)
        md += weeklyMarkdownSection(title: "This week",
                                    subtitle: "Items going live this week",
                                    range: rollup.thisWeekRange,
                                    items: rollup.thisWeek)
        md += weeklyMarkdownSection(title: "Next week",
                                    subtitle: "Items going live the following week",
                                    range: rollup.nextWeekRange,
                                    items: rollup.nextWeek)
        md += "## Not in production · \(rollup.notInProduction.count) item\(rollup.notInProduction.count == 1 ? "" : "s")\n\n"
        md += "Active clips that haven't reached the Production stage yet.\n\n"
        if rollup.notInProduction.isEmpty {
            md += "_Everything's in production._\n\n"
        } else {
            md += "| Status | Persona | Title | Go-Live |\n"
            md += "|---|---|---|---|\n"
            for item in rollup.notInProduction {
                let title = item.clip.title.isEmpty ? "Untitled" : item.clip.title
                md += "| \(item.clip.statusEnum.label) | \(item.clip.personaCode) | \(title.replacingOccurrences(of: "|", with: "\\|")) | \(item.clip.goLiveDate ?? "—") |\n"
            }
            md += "\n"
        }
        return md
    }

    private static func weeklyMarkdownSection(
        title: String,
        subtitle: String,
        range: (start: Date, end: Date),
        items: [ReportService.WeeklyRollup.Item]
    ) -> String {
        var md = "## \(title) · \(formatRange(range)) · \(items.count) item\(items.count == 1 ? "" : "s")\n\n"
        md += "_\(subtitle)_\n\n"
        if items.isEmpty {
            md += "_Nothing scheduled._\n\n"
            return md
        }
        md += "| Date | Persona | Title | Status |\n"
        md += "|---|---|---|---|\n"
        for item in items {
            let t = item.clip.title.isEmpty ? "Untitled" : item.clip.title
            md += "| \(item.clip.goLiveDate ?? "—") | \(item.clip.personaCode) | \(t.replacingOccurrences(of: "|", with: "\\|")) | \(item.clip.statusEnum.label) |\n"
        }
        md += "\n"
        return md
    }

    /// CSV with a "Section" column so consumers can ingest all four lists in
    /// one file. Order: Last Week → This Week → Next Week → Not In Production.
    static func exportWeeklyCSV(rollup: ReportService.WeeklyRollup) -> String {
        var lines = ["Section,Go-Live,Persona,Title,Status".self]
        let groups: [(String, [ReportService.WeeklyRollup.Item])] = [
            ("Last Week",        rollup.lastWeek),
            ("This Week",        rollup.thisWeek),
            ("Next Week",        rollup.nextWeek),
            ("Not In Production", rollup.notInProduction),
        ]
        for (section, items) in groups {
            for item in items {
                let row: [String] = [
                    section,
                    item.clip.goLiveDate ?? "",
                    item.clip.personaCode,
                    item.clip.title,
                    item.clip.statusEnum.label,
                ]
                lines.append(row.map { $0.csvEscaped }.joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Multi-page PDF rendered with the same `CGContext(consumer:)` pattern
    /// used by `exportPDFReport(clips:appState:)`. One section header + table
    /// per week, plus the not-in-production list at the end.
    static func exportWeeklyPDF(rollup: ReportService.WeeklyRollup, appState: AppState) -> Data {
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

        beginPage()
        line("Weekly Report", lineH: 26, bold: true)
        line("Anchor week: \(formatRange(rollup.thisWeekRange)) · exported \(isoNow())",
             lineH: 12, color: .secondaryLabelColor)
        fromTop += 8

        func renderWeek(title: String,
                        subtitle: String,
                        range: (start: Date, end: Date),
                        items: [ReportService.WeeklyRollup.Item]) {
            line("\(title) — \(formatRange(range))  ·  \(items.count) item\(items.count == 1 ? "" : "s")",
                 lineH: 16, bold: true)
            line(subtitle, lineH: 11, color: .secondaryLabelColor)
            fromTop += 4
            if items.isEmpty {
                line("(nothing scheduled)", lineH: 11, indent: 8, color: .tertiaryLabelColor)
                fromTop += 6
                return
            }
            // Header row
            ensureRoom(13)
            let cols: [CGFloat] = [90, 50, 290, 80]
            let labels = ["Go-Live", "Persona", "Title", "Status"]
            for (i, l) in labels.enumerated() {
                draw(l, x: margin + cols[..<i].reduce(0, +), lineH: 11, bold: true)
            }
            fromTop += 13
            for item in items {
                ensureRoom(12)
                let titleStr = item.clip.title.isEmpty ? "Untitled" : item.clip.title
                let truncated = titleStr.count > 50 ? String(titleStr.prefix(48)) + "…" : titleStr
                let cells = [
                    item.clip.goLiveDate ?? "—",
                    item.clip.personaCode,
                    truncated,
                    item.clip.statusEnum.label,
                ]
                for (i, c) in cells.enumerated() {
                    draw(c, x: margin + cols[..<i].reduce(0, +), lineH: 11)
                }
                fromTop += 12
            }
            fromTop += 8
        }

        renderWeek(title: "Last week",
                   subtitle: "Items that went live last week",
                   range: rollup.lastWeekRange,
                   items: rollup.lastWeek)
        renderWeek(title: "This week",
                   subtitle: "Items going live this week",
                   range: rollup.thisWeekRange,
                   items: rollup.thisWeek)
        renderWeek(title: "Next week",
                   subtitle: "Items going live the following week",
                   range: rollup.nextWeekRange,
                   items: rollup.nextWeek)

        // Not in production block
        line("Not in production  ·  \(rollup.notInProduction.count) item\(rollup.notInProduction.count == 1 ? "" : "s")",
             lineH: 16, bold: true)
        line("Active clips that haven't reached the Production stage yet.",
             lineH: 11, color: .secondaryLabelColor)
        fromTop += 4
        if rollup.notInProduction.isEmpty {
            line("(everything is in production)", lineH: 11, indent: 8, color: .tertiaryLabelColor)
        } else {
            ensureRoom(13)
            let cols: [CGFloat] = [90, 50, 290, 80]
            let labels = ["Status", "Persona", "Title", "Go-Live"]
            for (i, l) in labels.enumerated() {
                draw(l, x: margin + cols[..<i].reduce(0, +), lineH: 11, bold: true)
            }
            fromTop += 13
            for item in rollup.notInProduction {
                ensureRoom(12)
                let titleStr = item.clip.title.isEmpty ? "Untitled" : item.clip.title
                let truncated = titleStr.count > 50 ? String(titleStr.prefix(48)) + "…" : titleStr
                let cells = [
                    item.clip.statusEnum.label,
                    item.clip.personaCode,
                    truncated,
                    item.clip.goLiveDate ?? "—",
                ]
                for (i, c) in cells.enumerated() {
                    draw(c, x: margin + cols[..<i].reduce(0, +), lineH: 11)
                }
                fromTop += 12
            }
        }

        ctx.endPDFPage()
        ctx.closePDF()
        return pdf as Data
    }

    private static func formatRange(_ range: (start: Date, end: Date)) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: range.end) ?? range.end
        return "\(f.string(from: range.start)) – \(f.string(from: lastDay))"
    }

    // MARK: - Posting status report

    static func exportPostingStatusCSV(rows: [ReportService.PostingStatusRow]) -> String {
        var lines = ["Clip ID,Persona,Title,Site Code,Site Name,Posted,Posted Date"]
        for r in rows {
            lines.append([
                r.clipId, r.personaCode, r.clipTitle, r.siteCode, r.siteName,
                r.posted ? "yes" : "no", r.postedDate ?? ""
            ].map { $0.csvEscaped }.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static func exportPostingStatusMarkdown(rows: [ReportService.PostingStatusRow]) -> String {
        var md = "# Posting Status Report\n\n"
        md += "_\(rows.count) (clip × site) pair\(rows.count == 1 ? "" : "s") · exported \(isoNow())_\n\n"
        md += "| Clip ID | Persona | Title | Site | Posted | Date |\n"
        md += "|---|---|---|---|---|---|\n"
        for r in rows {
            let title = r.clipTitle.replacingOccurrences(of: "|", with: "\\|")
            md += "| `\(r.clipId)` | \(r.personaCode) | \(title) | \(r.siteName) (\(r.siteCode)) | \(r.posted ? "✓" : "—") | \(r.postedDate ?? "—") |\n"
        }
        return md
    }

    static func exportPostingStatusPDF(rows: [ReportService.PostingStatusRow]) -> Data {
        renderPDF(title: "Posting Status Report",
                  subtitle: "\(rows.count) (clip × site) pair\(rows.count == 1 ? "" : "s")",
                  columns: [(label: "Clip ID", width: 110), (label: "Persona", width: 50),
                            (label: "Title", width: 220), (label: "Site", width: 90),
                            (label: "Posted", width: 50)],
                  rows: rows.map { r -> [String] in
                      [r.clipId, r.personaCode,
                       r.clipTitle.count > 38 ? String(r.clipTitle.prefix(36)) + "…" : r.clipTitle,
                       r.siteCode, r.posted ? r.postedDate ?? "yes" : "—"]
                  })
    }

    // MARK: - Category usage report

    static func exportCategoryUsageCSV(rows: [ReportService.CategoryUsageRow]) -> String {
        var lines = ["Category,Clip Count"]
        for r in rows {
            lines.append([r.name, "\(r.clipCount)"].map { $0.csvEscaped }.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static func exportCategoryUsageMarkdown(rows: [ReportService.CategoryUsageRow]) -> String {
        var md = "# Category Usage Report\n\n"
        md += "_\(rows.count) categor\(rows.count == 1 ? "y" : "ies") · exported \(isoNow())_\n\n"
        md += "| Category | Clip count |\n|---|---|\n"
        for r in rows {
            md += "| \(r.name.replacingOccurrences(of: "|", with: "\\|")) | \(r.clipCount) |\n"
        }
        return md
    }

    static func exportCategoryUsagePDF(rows: [ReportService.CategoryUsageRow]) -> Data {
        renderPDF(title: "Category Usage Report",
                  subtitle: "\(rows.count) categor\(rows.count == 1 ? "y" : "ies")",
                  columns: [(label: "Category", width: 320), (label: "Clip count", width: 90)],
                  rows: rows.map { ["\($0.name)", "\($0.clipCount)"] })
    }

    // MARK: - Clip audit report

    static func exportAuditCSV(results: [ClipAuditService.Result]) -> String {
        var lines = ["Clip ID,Persona,Title,Status,Issue"]
        for r in results {
            if r.issues.isEmpty {
                lines.append([r.clipId, r.personaCode, r.title, "clean", ""]
                    .map { $0.csvEscaped }.joined(separator: ","))
            } else {
                for issue in r.issues {
                    lines.append([r.clipId, r.personaCode, r.title, "failing", issue.label]
                        .map { $0.csvEscaped }.joined(separator: ","))
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    static func exportAuditMarkdown(results: [ClipAuditService.Result]) -> String {
        let failing = results.filter { !$0.ok }
        let clean   = results.filter(\.ok)
        var md = "# Clip Audit Report\n\n"
        md += "_\(failing.count) failing · \(clean.count) clean · exported \(isoNow())_\n\n"
        md += "## Failing clips\n\n"
        if failing.isEmpty {
            md += "_None — every clip passed the audit._\n\n"
        } else {
            for r in failing {
                let t = r.title.isEmpty ? "Untitled" : r.title
                md += "### \(t.replacingOccurrences(of: "|", with: "\\|"))  \n"
                md += "`\(r.clipId)` · \(r.personaCode)\n\n"
                for issue in r.issues {
                    md += "- \(issue.label)\n"
                }
                md += "\n"
            }
        }
        return md
    }

    static func exportAuditPDF(results: [ClipAuditService.Result]) -> Data {
        let failing = results.filter { !$0.ok }
        let clean   = results.filter(\.ok)

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

        beginPage()
        line("Clip Audit Report", lineH: 26, bold: true)
        line("\(failing.count) failing · \(clean.count) clean · exported \(isoNow())",
             lineH: 12, color: .secondaryLabelColor)
        fromTop += 8

        if failing.isEmpty {
            line("Every clip passed the audit. 🎉", lineH: 14, color: .secondaryLabelColor)
        } else {
            for r in failing {
                ensureRoom(60)
                let t = r.title.isEmpty ? "Untitled" : r.title
                line(t, lineH: 16, bold: true)
                line("\(r.clipId) · \(r.personaCode)", lineH: 11, color: .secondaryLabelColor)
                for issue in r.issues {
                    line("• \(issue.label)", lineH: 11, indent: 14)
                }
                fromTop += 6
            }
        }

        ctx.endPDFPage()
        ctx.closePDF()
        return pdf as Data
    }

    // MARK: - Generic table-style PDF helper

    private static func renderPDF(title: String,
                                  subtitle: String,
                                  columns: [(label: String, width: CGFloat)],
                                  rows: [[String]]) -> Data {
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

        beginPage()
        ensureRoom(40)
        draw(title, x: margin, lineH: 26, bold: true); fromTop += 26
        draw("\(subtitle) · exported \(isoNow())", x: margin, lineH: 12, color: .secondaryLabelColor); fromTop += 16

        // Header
        ensureRoom(14)
        var x = margin
        for c in columns {
            draw(c.label, x: x, lineH: 12, bold: true)
            x += c.width
        }
        fromTop += 14

        // Rows
        for r in rows {
            ensureRoom(12)
            x = margin
            for (i, c) in columns.enumerated() {
                let cell = i < r.count ? r[i] : ""
                draw(cell, x: x, lineH: 11)
                x += c.width
            }
            fromTop += 12
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
