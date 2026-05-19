import Foundation

/// CSV writer. Reuses `ExportService.csvEscape` + `renderCell` so the
/// cell-formatting rules stay in one place across the legacy
/// "Export all fields" pipeline and Purple Export's user-chosen
/// subset.
@MainActor
final class CSVWriter: PurpleExportWriter {

    var format: PurpleExport.DestinationFormat { .csv }

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
        let delimiter = options.csvDelimiter.first.map(String.init) ?? ","

        // Header row: "id" + user-chosen field headers + created_at + updated_at.
        // Matches the column shape ExportService.formatCSV produces
        // for the legacy all-fields export, so a user who's mentally
        // modeling the output stays oriented.
        var headers = ["id"] + selections.map(\.header) + ["created_at", "updated_at"]
        var rows: [[String]] = [headers]

        for record in records {
            var cells: [String] = [record.id]
            for sel in selections {
                let raw = record.fields[sel.fieldKey]
                let fieldInfo = fieldByKey[sel.fieldKey]
                let rendered = ExportService.renderCell(
                    raw,
                    kind: fieldInfo?.kind ?? .text,
                    options: fieldInfo?.options ?? [],
                    linkTitle: linkResolver,
                    attachmentLabel: attachmentResolver
                )
                cells.append(rendered)
            }
            cells.append(record.createdAt)
            cells.append(record.updatedAt)
            rows.append(cells)
        }

        let body = rows.map { row in
            row.map(escape).joined(separator: delimiter)
        }.joined(separator: "\n") + "\n"

        let data = body.data(using: .utf8) ?? Data()
        try data.write(to: destination, options: .atomic)
        _ = headers  // silence unused-var when refactored
        return data.count
    }

    private func escape(_ s: String) -> String {
        if options.csvQuoteAlways {
            let inner = s.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(inner)\""
        }
        return ExportService.csvEscape(s)
    }
}
