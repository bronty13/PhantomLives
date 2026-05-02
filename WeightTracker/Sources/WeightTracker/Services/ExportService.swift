import Foundation
import AppKit
import SwiftUI

struct ExportService {

    // MARK: - CSV

    static func exportCSV(entries: [WeightEntry], unit: WeightUnit) -> String {
        var lines = ["Date,Weight (\(unit.label)),Notes"]
        for e in entries.sorted(by: { $0.date < $1.date }) {
            let w = String(format: "%.2f", e.displayWeight(unit: unit))
            let notes = e.notesMd.replacingOccurrences(of: "\"", with: "\"\"")
            lines.append("\"\(e.date)\",\(w),\"\(notes)\"")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Markdown

    static func exportMarkdown(entries: [WeightEntry], unit: WeightUnit, stats: WeightStats?, username: String) -> String {
        var md = "# Weight Tracker — \(username)\n\n"
        md += "_Exported \(iso(Date()))_\n\n"

        if let s = stats {
            md += "## Summary\n\n"
            md += "| | |\n|---|---|\n"
            md += "| Starting Weight | \(fmt(s.startWeight, unit: unit)) |\n"
            md += "| Current Weight | \(fmt(s.currentWeight, unit: unit)) |\n"
            if let gw = s.goalWeight { md += "| Goal Weight | \(fmt(gw, unit: unit)) |\n" }
            md += "| Total Change | \(fmtChange(s.totalChange, unit: unit)) |\n"
            if let wk = s.averageWeeklyChange { md += "| Avg Weekly Change | \(fmtChange(wk, unit: unit)) |\n" }
            if let pct = s.percentToGoal { md += "| Progress to Goal | \(String(format: "%.1f", pct))% |\n" }
            if let days = s.daysToGoal { md += "| Est. Days to Goal | \(days) |\n" }
            md += "\n"
        }

        md += "## All Entries\n\n"
        md += "| Date | Weight | Notes |\n|---|---|---|\n"
        for e in entries.sorted(by: { $0.date < $1.date }) {
            let w = fmt(e.displayWeight(unit: unit), unit: unit)
            let notes = e.notesMd.isEmpty ? "" : e.notesMd.replacingOccurrences(of: "\n", with: " ")
            md += "| \(e.date) | \(w) | \(notes) |\n"
        }
        return md
    }

    // MARK: - XLSX (minimal OOXML writer)

    static func exportXLSX(entries: [WeightEntry], unit: WeightUnit) -> Data? {
        let sorted = entries.sorted { $0.date < $1.date }
        var rows = [["Date", "Weight (\(unit.label))", "Notes"]]
        for e in sorted {
            rows.append([e.date, String(format: "%.2f", e.displayWeight(unit: unit)), e.notesMd])
        }
        return buildXLSX(rows: rows)
    }

    private static func buildXLSX(rows: [[String]]) -> Data? {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
             .replacingOccurrences(of: "\"", with: "&quot;")
        }

        var sheetRows = ""
        for (ri, row) in rows.enumerated() {
            sheetRows += "<row r=\"\(ri + 1)\">"
            for (ci, cell) in row.enumerated() {
                let col = xlsxCol(ci)
                let ref = "\(col)\(ri + 1)"
                sheetRows += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t>\(esc(cell))</t></is></c>"
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
        <sheets><sheet name="WeightData" sheetId="1" r:id="rId1"/></sheets>
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

        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("wt-xlsx-\(UUID().uuidString)")
        let xlDir = tmpDir.appendingPathComponent("xl/worksheets", isDirectory: true)
        let relsDir = tmpDir.appendingPathComponent("_rels", isDirectory: true)
        let xlRelsDir = tmpDir.appendingPathComponent("xl/_rels", isDirectory: true)

        do {
            try fm.createDirectory(at: xlDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: relsDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: xlRelsDir, withIntermediateDirectories: true)

            try contentTypesXML.data(using: .utf8)!.write(to: tmpDir.appendingPathComponent("[Content_Types].xml"))
            try dotRelsXML.data(using: .utf8)!.write(to: relsDir.appendingPathComponent(".rels"))
            try workbookXML.data(using: .utf8)!.write(to: tmpDir.appendingPathComponent("xl/workbook.xml"))
            try wbRelsXML.data(using: .utf8)!.write(to: xlRelsDir.appendingPathComponent("workbook.xml.rels"))
            try sheetXML.data(using: .utf8)!.write(to: xlDir.appendingPathComponent("sheet1.xml"))

            let zipURL = fm.temporaryDirectory.appendingPathComponent("wt-\(UUID().uuidString).xlsx")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-rqX", zipURL.path, "."]
            process.currentDirectoryURL = tmpDir
            try process.run()
            process.waitUntilExit()

            let data = try Data(contentsOf: zipURL)
            try? fm.removeItem(at: tmpDir)
            try? fm.removeItem(at: zipURL)
            return data
        } catch {
            try? fm.removeItem(at: tmpDir)
            return nil
        }
    }

    private static func xlsxCol(_ index: Int) -> String {
        var n = index
        var result = ""
        repeat {
            result = String(UnicodeScalar(65 + (n % 26))!) + result
            n = n / 26 - 1
        } while n >= 0
        return result
    }

    // MARK: - DOCX (minimal OOXML writer)

    static func exportDOCX(entries: [WeightEntry], unit: WeightUnit, stats: WeightStats?, username: String) -> Data? {
        let sorted = entries.sorted { $0.date < $1.date }
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
        }
        func row(_ cells: [String], bold: Bool = false) -> String {
            let bold_ = bold ? "<w:rPr><w:b/></w:rPr>" : ""
            let tds = cells.map { "<w:tc><w:p><w:r>\(bold_)<w:t>\(esc($0))</w:t></w:r></w:p></w:tc>" }.joined()
            return "<w:tr>\(tds)</w:tr>"
        }

        var tableRows = row(["Date", "Weight (\(unit.label))", "Notes"], bold: true)
        for e in sorted {
            tableRows += row([e.date, String(format: "%.2f", e.displayWeight(unit: unit)), e.notesMd])
        }

        var summaryPara = ""
        if let s = stats {
            summaryPara = "<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Summary</w:t></w:r></w:p>"
            summaryPara += "<w:p><w:r><w:t>Starting: \(fmt(s.startWeight, unit: unit)) | Current: \(fmt(s.currentWeight, unit: unit)) | Change: \(fmtChange(s.totalChange, unit: unit))</w:t></w:r></w:p>"
        }

        let docXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>
        <w:p><w:r><w:rPr><w:b/><w:sz w:val="32"/></w:rPr><w:t>Weight Tracker — \(esc(username))</w:t></w:r></w:p>
        <w:p><w:r><w:t>Exported \(iso(Date()))</w:t></w:r></w:p>
        \(summaryPara)
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

        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("wt-docx-\(UUID().uuidString)")
        let wordDir = tmpDir.appendingPathComponent("word", isDirectory: true)
        let relsDir = tmpDir.appendingPathComponent("_rels", isDirectory: true)

        do {
            try fm.createDirectory(at: wordDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: relsDir, withIntermediateDirectories: true)
            try contentTypesXML.data(using: .utf8)!.write(to: tmpDir.appendingPathComponent("[Content_Types].xml"))
            try dotRelsXML.data(using: .utf8)!.write(to: relsDir.appendingPathComponent(".rels"))
            try docXML.data(using: .utf8)!.write(to: wordDir.appendingPathComponent("document.xml"))

            let zipURL = fm.temporaryDirectory.appendingPathComponent("wt-\(UUID().uuidString).docx")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-rqX", zipURL.path, "."]
            process.currentDirectoryURL = tmpDir
            try process.run()
            process.waitUntilExit()

            let data = try Data(contentsOf: zipURL)
            try? fm.removeItem(at: tmpDir)
            try? fm.removeItem(at: zipURL)
            return data
        } catch {
            try? fm.removeItem(at: tmpDir)
            return nil
        }
    }

    // MARK: - PDF Report

    @MainActor
    static func exportPDFReport(
        entries: [WeightEntry],
        stats: WeightStats?,
        unit: WeightUnit,
        username: String,
        chartImage: NSImage?
    ) -> Data {
        let pageW: CGFloat = 612
        let pageH: CGFloat = 792
        let margin: CGFloat = 50
        let pdf = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: CGSize(width: pageW, height: pageH))

        guard let ctx = CGContext(consumer: CGDataConsumer(data: pdf as CFMutableData)!, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        // fromTop: distance from top of page (screen-like). Convert to PDF y = pageH - fromTop - lineH.
        var fromTop: CGFloat = margin

        func beginPage() {
            ctx.beginPDFPage(nil)
            // NSAttributedString.draw(at:) requires NSGraphicsContext.current to be the PDF context.
            // flipped:false = standard PDF origin (bottom-left); we convert coordinates manually.
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            fromTop = margin
        }

        func ensureRoom(_ h: CGFloat) {
            if fromTop + h > pageH - margin {
                ctx.endPDFPage()
                beginPage()
            }
        }

        func drawString(_ text: String, x: CGFloat, lineH: CGFloat, bold: Bool = false) {
            let font = bold ? NSFont.boldSystemFont(ofSize: lineH * 0.75)
                            : NSFont.systemFont(ofSize: lineH * 0.75)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            // PDF coords: baseline sits lineH*0.25 above the bottom of the line box
            NSAttributedString(string: text, attributes: attrs)
                .draw(at: CGPoint(x: x, y: pageH - fromTop - lineH + lineH * 0.25))
        }

        func line(_ text: String, lineH: CGFloat, bold: Bool = false, indent: CGFloat = 0) {
            ensureRoom(lineH)
            drawString(text, x: margin + indent, lineH: lineH, bold: bold)
            fromTop += lineH
        }

        beginPage()

        // Header
        line("Weight Tracker", lineH: 28, bold: true)
        line(username, lineH: 20)
        line("Exported \(iso(Date()))", lineH: 14)
        fromTop += 10

        // Stats summary
        if let s = stats {
            let pairs: [(String, String)] = [
                ("Starting Weight",   fmt(s.startWeight, unit: unit)),
                ("Current Weight",    fmt(s.currentWeight, unit: unit)),
                ("Total Change",      fmtChange(s.totalChange, unit: unit)),
                ("Avg Weekly Change", s.averageWeeklyChange.map { fmtChange($0, unit: unit) } ?? "—"),
                ("Progress to Goal",  s.percentToGoal.map { String(format: "%.1f%%", $0) } ?? "—"),
                ("Days to Goal",      s.daysToGoal.map { "\($0)" } ?? "—"),
                ("BMI",               s.bmi.map { String(format: "%.1f", $0) } ?? "—"),
            ]
            line("Summary", lineH: 18, bold: true)
            fromTop += 2
            for (label, value) in pairs {
                line("\(label):  \(value)", lineH: 14, indent: 10)
            }
            fromTop += 10
        }

        // Chart image (CGContext draw — not affected by NSGraphicsContext)
        if let img = chartImage {
            let imgH: CGFloat = 160
            ensureRoom(imgH + 10)
            let imgRect = CGRect(x: margin, y: pageH - fromTop - imgH,
                                 width: pageW - margin * 2, height: imgH)
            if let tiff = img.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let cgImg = bitmap.cgImage {
                ctx.draw(cgImg, in: imgRect)
            }
            fromTop += imgH + 10
        }

        // Entries table
        line("All Entries", lineH: 18, bold: true)
        fromTop += 2

        let colWidths: [CGFloat] = [90, 80, 310]
        let headers = ["Date", "Weight (\(unit.label))", "Notes"]

        ensureRoom(14)
        for (i, h) in headers.enumerated() {
            let x = margin + colWidths[..<i].reduce(0, +)
            drawString(h, x: x, lineH: 12, bold: true)
        }
        fromTop += 13

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            ensureRoom(12)
            let cols = [entry.date,
                        String(format: "%.2f", entry.displayWeight(unit: unit)),
                        entry.notesMd.count > 55 ? String(entry.notesMd.prefix(52)) + "…" : entry.notesMd]
            for (i, col) in cols.enumerated() {
                let x = margin + colWidths[..<i].reduce(0, +)
                drawString(col, x: x, lineH: 11)
            }
            fromTop += 12
        }

        ctx.endPDFPage()
        ctx.closePDF()
        return pdf as Data
    }

    // MARK: - Helpers

    private static func iso(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }

    static func fmt(_ value: Double, unit: WeightUnit) -> String {
        let v = unit == .lbs ? value : value * 0.453592
        return String(format: "%.1f \(unit.label)", v)
    }

    static func fmtChange(_ value: Double, unit: WeightUnit) -> String {
        let v = unit == .lbs ? value : value * 0.453592
        let sign = v < 0 ? "" : "+"
        return String(format: "\(sign)%.1f \(unit.label)", v)
    }
}
