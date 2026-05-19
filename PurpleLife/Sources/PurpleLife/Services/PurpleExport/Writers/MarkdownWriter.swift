import Foundation

/// Markdown writer. Two shapes: a GFM pipe table (the default —
/// round-trips through `MarkdownReader.parseAllTables`) or a
/// list-per-record layout (`## Title \n - key: value`). The pipe-
/// table cell shape uses the same `markdownEscape` rule
/// ExportService applies to the legacy "Export Markdown" toolbar
/// item, so a stack-trace-grep across the codebase doesn't surface
/// two different escape conventions.
@MainActor
final class MarkdownWriter: PurpleExportWriter {

    var format: PurpleExport.DestinationFormat { .markdown }

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
        let title = type.pluralName.isEmpty ? type.name : type.pluralName

        var out = ""
        switch options.markdownShape {
        case .table:
            out += "# \(title)\n\n"
            out += "_\(records.count) record\(records.count == 1 ? "" : "s")_\n\n"
            let headers = ["id"] + selections.map(\.header) + ["created_at", "updated_at"]
            out += "| " + headers.map(ExportService.markdownEscape).joined(separator: " | ") + " |\n"
            out += "| " + headers.map { _ in "---" }.joined(separator: " | ") + " |\n"
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
                out += "| " + cells.map(ExportService.markdownEscape).joined(separator: " | ") + " |\n"
            }
        case .listPerRecord:
            out += "# \(title)\n\n"
            for record in records {
                out += "## Record \(record.id)\n\n"
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
                    out += "- **\(sel.header):** \(value)\n"
                }
                out += "- _created_at:_ \(record.createdAt)\n"
                out += "- _updated_at:_ \(record.updatedAt)\n\n"
            }
        }

        let data = out.data(using: .utf8) ?? Data()
        try data.write(to: destination, options: .atomic)
        return data.count
    }
}
