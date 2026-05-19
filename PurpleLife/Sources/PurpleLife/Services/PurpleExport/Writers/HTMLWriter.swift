import Foundation

/// HTML writer. Stand-alone document with inline CSS — the same
/// shape `ExportService.formatHTML` produces for the legacy export,
/// but with the user-chosen field subset and header overrides
/// applied. PDFWriter reuses the bytes from here through the
/// existing WKWebView render path.
@MainActor
final class HTMLWriter: PurpleExportWriter {

    var format: PurpleExport.DestinationFormat { .html }

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
        let html = renderHTML(
            type: type,
            fields: fields,
            selections: selections,
            records: records,
            linkResolver: linkResolver,
            attachmentResolver: attachmentResolver
        )
        let data = html.data(using: .utf8) ?? Data()
        try data.write(to: destination, options: .atomic)
        return data.count
    }

    /// Returns the rendered HTML string. Exposed at instance level so
    /// PDFWriter can grab the bytes without round-tripping through
    /// disk.
    func renderHTML(
        type: SourceTypeInfo,
        fields: [SourceFieldInfo],
        selections: [PurpleExport.FieldSelection],
        records: [SourceRecord],
        linkResolver: (String) -> String?,
        attachmentResolver: (String) -> String?
    ) -> String {
        let fieldByKey = Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0) })
        let title = type.pluralName.isEmpty ? type.name : type.pluralName
        let escape = ExportService.htmlEscape

        let headers = ["id"] + selections.map(\.header) + ["created_at", "updated_at"]
        let headerHTML = headers.map { "<th>\(escape($0))</th>" }.joined()

        var rowsHTML = ""
        for record in records {
            var cells: [String] = [record.id]
            for sel in selections {
                let raw = record.fields[sel.fieldKey]
                let info = fieldByKey[sel.fieldKey]
                cells.append(ExportService.renderCell(
                    raw,
                    kind: info?.kind ?? .text,
                    options: info?.options ?? [],
                    linkTitle: linkResolver,
                    attachmentLabel: attachmentResolver
                ))
            }
            cells.append(record.createdAt)
            cells.append(record.updatedAt)
            rowsHTML += "    <tr>" + cells.map { "<td>\(escape($0))</td>" }.joined() + "</tr>\n"
        }

        // Inline CSS — same purple palette as ExportService's
        // existing HTML export so the two flows produce visually-
        // consistent output.
        let css = """
        body { font-family: -apple-system, system-ui, "Helvetica Neue", sans-serif;
               background: #FAF9FC; color: #2A2840; margin: 32px; }
        h1 { color: #4F2D86; }
        table { border-collapse: collapse; width: 100%; background: #FFFFFF;
                box-shadow: 0 1px 3px rgba(0,0,0,0.05); }
        th { text-align: left; padding: 10px 12px; background: #ECE7F6;
             color: #4F2D86; font-weight: 600; font-size: 12px;
             text-transform: uppercase; letter-spacing: 0.5px;
             border-bottom: 1px solid #DDD3F0; }
        td { padding: 10px 12px; border-bottom: 1px solid #F0EAF8;
             font-size: 13px; vertical-align: top; }
        tr:hover td { background: #FAF7FE; }
        .meta { color: #7B6FA0; font-size: 12px; margin-bottom: 16px; }
        """

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <title>\(escape(title)) — PurpleLife</title>
          <style>\(css)</style>
        </head>
        <body>
          <h1>\(escape(title))</h1>
          <div class="meta">\(records.count) record\(records.count == 1 ? "" : "s") · exported by Purple Export</div>
          <table>
            <thead><tr>\(headerHTML)</tr></thead>
            <tbody>
        \(rowsHTML)    </tbody>
          </table>
        </body>
        </html>
        """
    }
}
