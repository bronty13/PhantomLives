import Foundation
import AppKit
import SwiftUI

/// Export & clipboard service. Renders a Matter (plus its notes / time entries
/// / attachments metadata) into Markdown / PDF / DOCX, copies briefs to the
/// pasteboard, and writes files to the configured export directory.
@MainActor
enum ExportService {

    enum Format: String, CaseIterable, Identifiable {
        case markdown, pdf, docx
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .markdown: return "Markdown (.md)"
            case .pdf:      return "PDF (.pdf)"
            case .docx:     return "Word (.docx)"
            }
        }
        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .pdf:      return "pdf"
            case .docx:     return "docx"
            }
        }
    }

    // MARK: - Brief / clipboard

    /// `MatterID • Title • Date Opened • Status` per the spec.
    static func brief(_ m: Matter) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        let opened = df.string(from: m.createdAt)
        return "\(m.id) • \(m.title.isEmpty ? "(untitled)" : m.title) • \(opened) • \(m.status)"
    }

    static func copyBrief(_ m: Matter) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(brief(m), forType: .string)
    }

    static func copyMarkdown(_ m: Matter, types: [MatterType], notes: [Note], timeEntries: [TimeEntry], attachments: [Attachment], settings: AppSettings) {
        let md = renderMarkdown(matter: m, types: types, notes: notes, timeEntries: timeEntries, attachments: attachments, settings: settings)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(md, forType: .string)
    }

    // MARK: - Markdown

    static func renderMarkdown(matter m: Matter, types: [MatterType], notes: [Note], timeEntries: [TimeEntry], attachments: [Attachment], settings: AppSettings) -> String {
        let typeName = types.first { $0.id == m.typeId }?.name ?? "Unknown"
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short

        var out = "# \(m.title.isEmpty ? "(untitled)" : m.title)\n\n"
        out += "**Matter ID:** `\(m.id)`  \n"
        out += "**Type:** \(typeName)  \n"
        out += "**Status:** \(m.status)  \n"
        if let due = m.dueAt { out += "**Due:** \(df.string(from: due))  \n" }
        out += "**Created:** \(df.string(from: m.createdAt))  \n"
        out += "**Last Modified:** \(df.string(from: m.modifiedAt))  \n"
        out += "**Last Accessed:** \(df.string(from: m.accessedAt))  \n"
        let total = timeEntries.reduce(0) { $0 + $1.seconds }
        out += "**Time Worked:** \(TimeFormat.hm(total))  \n"
        if !m.timeTrackingCode.isEmpty { out += "**Time Tracking Code:** \(m.timeTrackingCode)  \n" }

        out += "\n## References\n\n"
        if !m.fileStorePrimary.isEmpty   { out += "- **File Store (Primary):** `\(m.fileStorePrimary)`\n" }
        if !m.fileStoreSecondary.isEmpty { out += "- **File Store (Secondary):** `\(m.fileStoreSecondary)`\n" }
        if !m.external1Number.isEmpty || !m.external1Url.isEmpty {
            out += "- **\(settings.external1Label):** \(m.external1Number) \(m.external1Url.isEmpty ? "" : "<\(m.external1Url)>")\n"
        }
        if !m.external2Number.isEmpty || !m.external2Url.isEmpty {
            out += "- **\(settings.external2Label):** \(m.external2Number) \(m.external2Url.isEmpty ? "" : "<\(m.external2Url)>")\n"
        }
        if !m.external3Number.isEmpty || !m.external3Url.isEmpty {
            out += "- **\(settings.external3Label):** \(m.external3Number) \(m.external3Url.isEmpty ? "" : "<\(m.external3Url)>")\n"
        }

        if !m.descriptionMd.isEmpty { out += "\n## Description\n\n\(m.descriptionMd)\n" }
        if !m.notesMd.isEmpty       { out += "\n## Notes\n\n\(m.notesMd)\n" }

        if !notes.isEmpty {
            out += "\n## Notes Log\n\n"
            for n in notes {
                out += "### \(df.string(from: n.createdAt))\n\n\(n.bodyMd)\n\n"
            }
        }

        if !timeEntries.isEmpty {
            out += "\n## Time Entries\n\n"
            out += "| Started | Ended | Duration | Note |\n|---|---|---|---|\n"
            for e in timeEntries {
                let started = df.string(from: e.startedAt)
                let ended = e.endedAt.map { df.string(from: $0) } ?? "(running)"
                out += "| \(started) | \(ended) | \(TimeFormat.hm(e.seconds)) | \(e.note) |\n"
            }
            out += "\n**Total:** \(TimeFormat.hm(total))\n"
        }

        if !attachments.isEmpty {
            out += "\n## Attachments\n\n"
            out += "| Filename | Size | SHA1 |\n|---|---:|---|\n"
            for a in attachments {
                out += "| \(a.filename) | \(a.sizeBytes) | `\(a.sha1)` |\n"
            }
        }

        if !m.resolutionMd.isEmpty { out += "\n## Resolution\n\n\(m.resolutionMd)\n" }
        if !m.lessonsMd.isEmpty    { out += "\n## Lessons Learned\n\n\(m.lessonsMd)\n" }
        return out
    }

    // MARK: - PDF

    /// Render the markdown into an attributed string and print it through
    /// AppKit to a PDF.
    static func renderPDF(matter m: Matter, types: [MatterType], notes: [Note], timeEntries: [TimeEntry], attachments: [Attachment], settings: AppSettings, to url: URL) throws {
        let md = renderMarkdown(matter: m, types: types, notes: notes, timeEntries: timeEntries, attachments: attachments, settings: settings)
        // Use AppKit's NSAttributedString markdown initializer (macOS 13+).
        var opts = AttributedString.MarkdownParsingOptions()
        opts.interpretedSyntax = .inlineOnlyPreservingWhitespace
        let attr = (try? NSAttributedString(
            markdown: md,
            options: .init(interpretedSyntax: .full)
        )) ?? NSAttributedString(string: md)

        // Lay out into a text view and print to PDF.
        let pageSize = NSSize(width: 612, height: 792) // US Letter
        let inset: CGFloat = 54
        let textRect = NSRect(x: inset, y: inset,
                              width: pageSize.width - inset * 2,
                              height: pageSize.height - inset * 2)
        let textView = NSTextView(frame: textRect)
        textView.textStorage?.setAttributedString(attr)
        textView.isEditable = false

        let printInfo = NSPrintInfo()
        printInfo.paperSize = pageSize
        printInfo.topMargin = inset
        printInfo.bottomMargin = inset
        printInfo.leftMargin = inset
        printInfo.rightMargin = inset
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let op = NSPrintOperation(view: textView, printInfo: printInfo)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        let ok = op.run()
        if !ok { throw NSError(domain: "PurpleTracker.Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "PDF print operation failed"]) }
    }

    // MARK: - DOCX

    /// Build a minimal but valid `.docx` (ZIP of `[Content_Types].xml` +
    /// `_rels/.rels` + `word/document.xml`) from the markdown rendering.
    /// We escape XML chars and emit a paragraph per markdown line — this is
    /// not a full markdown-to-docx renderer, but it produces a Word-readable
    /// file that captures the report content.
    static func renderDOCX(matter m: Matter, types: [MatterType], notes: [Note], timeEntries: [TimeEntry], attachments: [Attachment], settings: AppSettings, to url: URL) throws {
        let md = renderMarkdown(matter: m, types: types, notes: notes, timeEntries: timeEntries, attachments: attachments, settings: settings)
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("pt-docx-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let wordDir = staging.appendingPathComponent("word", isDirectory: true)
        let relsDir = staging.appendingPathComponent("_rels", isDirectory: true)
        try fm.createDirectory(at: wordDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: relsDir, withIntermediateDirectories: true)

        try docxContentTypes.write(to: staging.appendingPathComponent("[Content_Types].xml"),
                                   atomically: true, encoding: .utf8)
        try docxRootRels.write(to: relsDir.appendingPathComponent(".rels"),
                               atomically: true, encoding: .utf8)
        try renderDocumentXML(markdown: md).write(
            to: wordDir.appendingPathComponent("document.xml"),
            atomically: true, encoding: .utf8
        )

        // Zip the staging directory to the destination.
        try? fm.removeItem(at: url)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.arguments = ["-rq", url.path, ".", "-x", "*.DS_Store"]
        proc.currentDirectoryURL = staging
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            throw NSError(domain: "PurpleTracker.Export", code: Int(proc.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "zip failed building .docx"])
        }
    }

    private static func renderDocumentXML(markdown: String) -> String {
        var body = ""
        for raw in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let style: String?
            let text: String
            if line.hasPrefix("### ")     { style = "Heading3"; text = String(line.dropFirst(4)) }
            else if line.hasPrefix("## ") { style = "Heading2"; text = String(line.dropFirst(3)) }
            else if line.hasPrefix("# ")  { style = "Heading1"; text = String(line.dropFirst(2)) }
            else                          { style = nil;        text = line }

            let escaped = text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let pPr = style.map { "<w:pPr><w:pStyle w:val=\"\($0)\"/></w:pPr>" } ?? ""
            body += "<w:p>\(pPr)<w:r><w:t xml:space=\"preserve\">\(escaped)</w:t></w:r></w:p>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>
        \(body)
        <w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>
        </w:body>
        </w:document>
        """
    }

    private static let docxContentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml"
        ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
    """

    private static let docxRootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """

    // MARK: - File output

    /// Render the requested format to `~/Downloads/PurpleTracker/<MatterID>.<ext>`
    /// (or wherever the user has overridden the export directory). Returns the
    /// final URL. Auto-creates the directory.
    @discardableResult
    static func exportToFile(format: Format, matter m: Matter, types: [MatterType], notes: [Note], timeEntries: [TimeEntry], attachments: [Attachment], settings: AppSettings, settingsStore: SettingsStore) throws -> URL {
        let dir = settingsStore.resolvedExportDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeTitle = FileStoreService.sanitize(m.title)
        let url = dir.appendingPathComponent("\(m.id) \(safeTitle).\(format.fileExtension)")
        switch format {
        case .markdown:
            let md = renderMarkdown(matter: m, types: types, notes: notes, timeEntries: timeEntries, attachments: attachments, settings: settings)
            try md.write(to: url, atomically: true, encoding: .utf8)
        case .pdf:
            try renderPDF(matter: m, types: types, notes: notes, timeEntries: timeEntries, attachments: attachments, settings: settings, to: url)
        case .docx:
            try renderDOCX(matter: m, types: types, notes: notes, timeEntries: timeEntries, attachments: attachments, settings: settings, to: url)
        }
        return url
    }
}
