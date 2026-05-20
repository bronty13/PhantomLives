import Foundation

/// Orchestrates one import: reads source rows via the chosen
/// `PurpleImportSourceReader`, transforms + coerces each row per the
/// `SavedImportMapping`, and writes records via the
/// `PurpleImportSink`.
///
/// Two modes:
///   • **Small** (≤ `PurpleImport.bulkThreshold` rows) — per-record
///     `sink.upsert(...)` so per-row errors surface immediately and
///     records appear in the UI as they land.
///   • **Bulk** (> threshold) — collect all coerced rows into memory,
///     materialize the new type (if any), then one `sink.bulkInsert`
///     call. Trades real-time visibility for one undo entry / one
///     CloudKit fan-out / one FTS pass.
///
/// Decision is made *after* the preview pass — by then the runner
/// knows the row count and can switch paths up front.
@MainActor
final class ImportRunner {

    let mapping: SavedImportMapping
    let reader: PurpleImportSourceReader
    let sink: PurpleImportSink
    let source: PurpleImport.SourceInput

    /// Materialized type id. When `mapping.newTypeTemplate != nil` the
    /// runner calls `sink.createType` first and stamps this property.
    /// Otherwise it equals `mapping.targetTypeId`.
    private(set) var resolvedTypeId: String?

    init(
        mapping: SavedImportMapping,
        reader: PurpleImportSourceReader,
        sink: PurpleImportSink,
        source: PurpleImport.SourceInput
    ) {
        self.mapping = mapping
        self.reader = reader
        self.sink = sink
        self.source = source
        reader.setOptions(mapping.sourceOptions.mapValues { (v: SourceOptionValue) in v.rawAny })
    }

    /// Run the import and stream events. Callers spawn this inside a
    /// `Task` (it's `@MainActor` because the sink is). Yields events
    /// as the run progresses; the caller is responsible for updating
    /// UI state on each.
    func run() -> AsyncThrowingStream<PurpleImport.RunEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                let startedAt = Date()
                var summary = PurpleImport.RunSummary(
                    inserted: 0,
                    updated: 0,
                    skipped: 0,
                    failed: 0,
                    startedAt: startedAt,
                    finishedAt: startedAt
                )
                do {
                    // 1. Resolve target type (create if proposed).
                    let typeId: String
                    if let proposal = self.materializedProposal() {
                        typeId = try self.sink.createType(proposal)
                    } else if let existing = self.mapping.targetTypeId {
                        typeId = existing
                    } else {
                        throw PurpleImportError.noTargetTypeChosen
                    }
                    self.resolvedTypeId = typeId

                    // 2. Pre-load source rows. Phase 1 reads
                    //    everything into memory before deciding small
                    //    vs bulk — the largest realistic CSV is a few
                    //    MB, well within budget. Streaming-bulk is a
                    //    Phase 2 optimization once we have larger
                    //    real-world inputs to size against.
                    var rows: [PurpleImport.SourceRow] = []
                    for try await row in self.reader.read(self.source) {
                        if Task.isCancelled { break }
                        rows.append(row)
                    }
                    continuation.yield(.willStart(totalRows: rows.count))

                    // 3. Coerce + transform per row.
                    let typeFields = try self.sink.listFields(typeId: typeId)
                    let fieldOptions = Dictionary(
                        uniqueKeysWithValues: typeFields.map { ($0.key, $0.options) }
                    )

                    // For new-type imports, the user defined the
                    // field kinds in step 3a. Those kinds are
                    // authoritative — the auto-inferred kind on the
                    // mapping row (which was derived from raw sample
                    // values, e.g. .number for an Excel-serial date
                    // column) would otherwise win during coercion
                    // and the field would land as the wrong type. Sync
                    // the mapping kinds to the target field kinds
                    // here whenever we own the type definition.
                    let effectiveMappings: [SavedImportMapping.FieldMapping]
                    if self.mapping.newTypeTemplate != nil {
                        let kindByKey = Dictionary(
                            uniqueKeysWithValues: typeFields.map { ($0.key, $0.kind) }
                        )
                        effectiveMappings = self.mapping.fieldMappings.map { m in
                            guard let kind = kindByKey[m.targetKey] else { return m }
                            var updated = m
                            updated.expectedKind = kind
                            return updated
                        }
                    } else {
                        effectiveMappings = self.mapping.fieldMappings
                    }

                    var coercedRows: [[String: Any]] = []
                    var coercionFailures: [(Int, String)] = []
                    for (i, row) in rows.enumerated() {
                        if Task.isCancelled { break }
                        switch self.coerceRow(
                            row,
                            mappings: effectiveMappings,
                            fieldOptions: fieldOptions
                        ) {
                        case .accepted(let dict):
                            coercedRows.append(dict)
                        case .skipped(let reason):
                            summary.skipped += 1
                            continuation.yield(.row(index: i, status: .skipped(reason: reason)))
                        case .failed(let reason):
                            coercionFailures.append((i, reason))
                            if self.mapping.fieldMappings.contains(where: { $0.onError == .abort }) {
                                throw PurpleImportError.coercionAborted(reason)
                            }
                            summary.failed += 1
                            continuation.yield(.row(index: i, status: .failed(reason: reason)))
                        }
                    }

                    // 4. Pick small vs bulk path.
                    if coercedRows.count >= PurpleImport.bulkThreshold,
                       self.mapping.upsertStrategy == .insertOnly {
                        let result = try self.sink.bulkInsert(typeId: typeId, rows: coercedRows)
                        summary.inserted += result.insertedRecordIds.count
                        for (i, recId) in result.insertedRecordIds.enumerated() {
                            continuation.yield(.row(index: i, status: .inserted))
                            _ = recId
                        }
                        for (idx, msg) in result.failures {
                            summary.failed += 1
                            continuation.yield(.row(index: idx, status: .failed(reason: msg)))
                        }
                    } else {
                        // Per-record path. Used for small imports
                        // OR any import with `upsertOnKey` — bulk
                        // path is insert-only by design.
                        for (i, values) in coercedRows.enumerated() {
                            if Task.isCancelled { break }
                            do {
                                let r = try self.sink.upsert(
                                    typeId: typeId,
                                    keyFieldKey: self.mapping.upsertStrategy == .upsertOnKey ? self.mapping.keyFieldKey : nil,
                                    values: values,
                                    attachments: []  // Phase 2: resolve attachment field values
                                )
                                switch r {
                                case .inserted:
                                    summary.inserted += 1
                                    continuation.yield(.row(index: i, status: .inserted))
                                case .updated:
                                    summary.updated += 1
                                    continuation.yield(.row(index: i, status: .updated))
                                case .skipped(let reason):
                                    summary.skipped += 1
                                    continuation.yield(.row(index: i, status: .skipped(reason: reason)))
                                }
                            } catch {
                                summary.failed += 1
                                continuation.yield(.row(
                                    index: i,
                                    status: .failed(reason: error.localizedDescription)
                                ))
                            }
                        }
                    }

                    summary.finishedAt = Date()
                    continuation.yield(.finished(summary: summary))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(message: error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Per-row coercion

    enum RowOutcome {
        case accepted([String: Any])
        case skipped(reason: String)
        case failed(reason: String)
    }

    private func coerceRow(
        _ row: PurpleImport.SourceRow,
        mappings: [SavedImportMapping.FieldMapping],
        fieldOptions: [String: [FieldOption]]
    ) -> RowOutcome {
        var values: [String: Any] = [:]
        for m in mappings {
            let raw = row.cell(at: m.source)
            let transformed = applyTransforms(raw, transforms: m.transforms)
            switch FieldValueCoercer.coerce(
                transformed,
                to: m.expectedKind,
                fieldOptions: fieldOptions[m.targetKey] ?? []
            ) {
            case .value(let v):
                values[m.targetKey] = v
            case .empty:
                switch m.onError {
                case .skipRow:
                    return .skipped(reason: "empty value for ‘\(m.targetKey)’")
                case .fillDefault:
                    if let def = m.defaultValue {
                        values[m.targetKey] = def.rawAny
                    }
                case .abort:
                    return .failed(reason: "empty value for ‘\(m.targetKey)’ aborted run")
                }
            case .failure(let err):
                switch m.onError {
                case .skipRow:
                    return .skipped(reason: err.description)
                case .fillDefault:
                    if let def = m.defaultValue {
                        values[m.targetKey] = def.rawAny
                    }
                case .abort:
                    return .failed(reason: err.description)
                }
            }
        }
        return .accepted(values)
    }

    private func applyTransforms(_ value: Any?, transforms: [SavedImportMapping.Transform]) -> Any? {
        guard var s = (value as? String) else { return value }
        for t in transforms {
            switch t {
            case .trim:        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            case .lowercase:   s = s.lowercased()
            case .uppercase:   s = s.uppercased()
            case .regexReplace(let p, let r):
                guard let re = try? NSRegularExpression(pattern: p, options: []) else { continue }
                let range = NSRange(s.startIndex..., in: s)
                s = re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: r)
            case .prefix(let p): s = p + s
            case .suffix(let p): s = s + p
            }
        }
        return s
    }

    // MARK: - Helpers

    private func materializedProposal() -> SinkTypeProposal? {
        guard let template = mapping.newTypeTemplate else { return nil }
        return SinkTypeProposal(
            name: template.name,
            pluralName: template.pluralName,
            systemImage: template.systemImage,
            colorHex: template.colorHex,
            fields: template.fields.map { f in
                SinkFieldProposal(
                    name: f.name,
                    kind: f.kind,
                    options: f.options,
                    required: f.required
                )
            },
            isVault: template.isVault
        )
    }
}

// MARK: - Errors

enum PurpleImportError: LocalizedError {
    case noTargetTypeChosen
    case noReaderForFormat(PurpleImport.SourceFormat)
    case coercionAborted(String)

    var errorDescription: String? {
        switch self {
        case .noTargetTypeChosen:
            return "No target type was chosen and no new-type template was supplied."
        case .noReaderForFormat(let f):
            return "No Purple Import reader is registered for \(f.displayName). It may not be enabled in this build."
        case .coercionAborted(let reason):
            return "Import aborted on a row: \(reason)"
        }
    }
}

/// Pick the right reader for a source format. Readers are added as
/// phases land — Phase 1 shipped CSV + JSON; Phase 2 adds Markdown +
/// XML. The wizard's format picker greys help text for formats whose
/// readers aren't wired yet.
@MainActor
enum PurpleImportReaderRegistry {
    static func reader(for format: PurpleImport.SourceFormat) throws -> PurpleImportSourceReader {
        switch format {
        case .csv:      return CSVReader()
        case .json:     return JSONReader()
        case .markdown: return MarkdownReader()
        case .xml:      return XMLReader()
        case .xlsx:     return XLSXReader()
        case .docx:     return DOCXReader()
        case .pdf:      return PDFReader()
        }
    }
}
