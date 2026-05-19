import Foundation

/// JSON writer. Three shapes, picked via `FormatOptions.jsonShape`:
///
///   • `.arrayOfObjects` — `[ { id, …field values…, created_at, updated_at }, … ]`
///     Round-trips through `JSONReader` as tabular records.
///   • `.ndjson` — one JSON object per line. Same shape as
///     arrayOfObjects but stream-friendly for downstream pipelines.
///   • `.nested` — `{ format: "purplelife.per-type-export.v1", type: {
///     id, name, pluralName, fields: [...] }, records: [...] }`.
///     Self-describing — a future reader can interpret each field's
///     kind without the live app.
///
/// Field values use coercion-friendly shapes (numbers as numbers
/// when the kind is `.number`, ISO-8601 dates as strings, etc.) so
/// the output is honest about types rather than stringifying
/// everything.
@MainActor
final class JSONWriter: PurpleExportWriter {

    var format: PurpleExport.DestinationFormat { .json }

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

        // Build each record's JSON shape. We keep numeric / boolean
        // values typed; everything else stringifies via renderCell
        // so links + attachments resolve to their human-readable
        // labels.
        let recordObjects: [[String: Any]] = records.map { record in
            var obj: [String: Any] = ["id": record.id]
            for sel in selections {
                let raw = record.fields[sel.fieldKey]
                let info = fieldByKey[sel.fieldKey]
                obj[sel.header] = jsonValue(
                    raw: raw,
                    kind: info?.kind ?? .text,
                    options: info?.options ?? [],
                    linkResolver: linkResolver,
                    attachmentResolver: attachmentResolver
                )
            }
            obj["created_at"] = record.createdAt
            obj["updated_at"] = record.updatedAt
            return obj
        }

        let data: Data
        switch options.jsonShape {
        case .arrayOfObjects:
            data = try encode(recordObjects as Any, pretty: options.jsonPrettyPrint)
        case .ndjson:
            var lines: [String] = []
            for obj in recordObjects {
                let bytes = try JSONSerialization.data(
                    withJSONObject: obj,
                    options: [.sortedKeys]
                )
                if let s = String(data: bytes, encoding: .utf8) { lines.append(s) }
            }
            let body = lines.joined(separator: "\n") + "\n"
            data = body.data(using: .utf8) ?? Data()
        case .nested:
            let envelope: [String: Any] = [
                "format": "purplelife.per-type-export.v1",
                "exportedAt": ISO8601DateFormatter().string(from: Date()),
                "type": [
                    "id": type.id,
                    "name": type.name,
                    "pluralName": type.pluralName,
                    "fields": selections.map { sel -> [String: Any] in
                        let info = fieldByKey[sel.fieldKey]
                        return [
                            "key": sel.fieldKey,
                            "header": sel.header,
                            "kind": info?.kind.rawValue ?? "text"
                        ]
                    }
                ],
                "records": recordObjects
            ]
            data = try encode(envelope, pretty: options.jsonPrettyPrint)
        }
        try data.write(to: destination, options: .atomic)
        return data.count
    }

    private func encode(_ value: Any, pretty: Bool) throws -> Data {
        var opts: JSONSerialization.WritingOptions = [.sortedKeys]
        if pretty { opts.insert(.prettyPrinted) }
        return try JSONSerialization.data(withJSONObject: value, options: opts)
    }

    /// Type-preserving projection. Numeric and Bool field kinds keep
    /// their JSON-native shape; everything else stringifies through
    /// `ExportService.renderCell` so link / attachment references
    /// resolve to user-readable labels rather than ids / hashes.
    private func jsonValue(
        raw: Any?,
        kind: FieldKind,
        options: [FieldOption],
        linkResolver: (String) -> String?,
        attachmentResolver: (String) -> String?
    ) -> Any {
        guard let raw, !(raw is NSNull) else { return NSNull() }
        switch kind {
        case .number:
            if let d = raw as? Double { return d }
            if let i = raw as? Int { return i }
            if let s = raw as? String, let d = Double(s) { return d }
            return NSNull()
        case .boolean:
            if let b = raw as? Bool { return b }
            if let s = raw as? String {
                let lower = s.lowercased()
                if ["true", "yes", "1"].contains(lower) { return true }
                if ["false", "no", "0"].contains(lower) { return false }
            }
            return NSNull()
        case .rating:
            if let n = raw as? Int { return n }
            if let s = raw as? String, let n = Int(s) { return n }
            return NSNull()
        default:
            return ExportService.renderCell(
                raw,
                kind: kind,
                options: options,
                linkTitle: linkResolver,
                attachmentLabel: attachmentResolver
            )
        }
    }
}
