import Foundation

/// Orchestrates one export run: resolves the target type + records
/// via the `PurpleExportSource`, picks the right `PurpleExportWriter`
/// for the chosen format, builds the destination path from the
/// config's filename template, and writes the output.
///
/// Mirror of `ImportRunner` on the export side. `@MainActor`
/// because the source + writers are MainActor-bound — same
/// rationale as Purple Import.
@MainActor
final class ExportRunner {

    let config: SavedExportConfig
    let source: PurpleExportSource
    /// Default landing directory when `config.destination.mode == .default`.
    /// Wired by `AppState` to `settingsStore.resolvedExportDirectory`.
    let defaultDirectory: URL

    init(config: SavedExportConfig, source: PurpleExportSource, defaultDirectory: URL) {
        self.config = config
        self.source = source
        self.defaultDirectory = defaultDirectory
    }

    func run() -> AsyncThrowingStream<PurpleExport.RunEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                let startedAt = Date()
                do {
                    guard let typeId = config.typeId else {
                        throw PurpleExportError.noTypeChosen
                    }
                    guard let writer = try Self.writer(for: config.format) else {
                        throw PurpleExportError.formatNotSupported(config.format)
                    }
                    writer.setOptions(config.formatOptions)

                    let typeInfos = try self.source.listTypes()
                    guard let type = typeInfos.first(where: { $0.id == typeId }) else {
                        throw PurpleExportError.typeNotFound(typeId)
                    }
                    let allFields = try self.source.listFields(typeId: typeId)
                    let selections = self.effectiveSelections(allFields: allFields)
                    let records = try self.source.fetchRecords(typeId: typeId, selector: config.selector)

                    continuation.yield(.willStart(totalRecords: records.count))

                    let destination = try self.resolveDestination(for: type)
                    try FileManager.default.createDirectory(
                        at: destination.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )

                    let bytes = try writer.write(
                        type: type,
                        fields: allFields,
                        selections: selections,
                        records: records,
                        linkResolver: { self.source.resolveLinkedTitle(recordId: $0) },
                        attachmentResolver: { self.source.resolveAttachmentLabel(sha256: $0) },
                        to: destination
                    )

                    continuation.yield(.wroteFile(at: destination, bytes: bytes))
                    let summary = PurpleExport.RunSummary(
                        recordCount: records.count,
                        fileURL: destination,
                        bytesOnDisk: bytes,
                        format: config.format,
                        startedAt: startedAt,
                        finishedAt: Date()
                    )
                    continuation.yield(.finished(summary: summary))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(message: error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Empty `config.fields` means "export every field" — populate
    /// from the type's full field list so the runner has a concrete
    /// list to project against. Headers default to field names.
    private func effectiveSelections(allFields: [SourceFieldInfo]) -> [PurpleExport.FieldSelection] {
        if !config.fields.isEmpty { return config.fields }
        return allFields.map { f in
            PurpleExport.FieldSelection(id: UUID().uuidString, fieldKey: f.key, header: f.name)
        }
    }

    /// Render the filename template + resolve the directory. Tokens
    /// match `ExportService.export(...)`'s legacy naming (so files
    /// dropped next to each other from either flow look consistent).
    private func resolveDestination(for type: SourceTypeInfo) throws -> URL {
        let directory: URL
        switch config.destination.mode {
        case .default:
            directory = defaultDirectory
        case .custom:
            guard let path = config.destination.customPath, !path.isEmpty else {
                throw PurpleExportError.missingCustomDestination
            }
            directory = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        let filename = renderFilename(template: config.destination.filenameTemplate, type: type)
        return directory.appendingPathComponent(filename)
    }

    private func renderFilename(template: String, type: SourceTypeInfo) -> String {
        let stamp = filenameStamp()
        let pluralSafe = ExportService.sanitizeFilename(type.pluralName.isEmpty ? type.name : type.pluralName)
        let nameSafe = ExportService.sanitizeFilename(type.name)
        return template
            .replacingOccurrences(of: "{type-plural}", with: pluralSafe)
            .replacingOccurrences(of: "{type-name}", with: nameSafe)
            .replacingOccurrences(of: "{stamp}", with: stamp)
            .replacingOccurrences(of: "{ext}", with: config.format.fileExtension)
    }

    private func filenameStamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }

    /// Pick the writer concrete for a destination format. All eight
    /// formats are wired as of Phase 5; the wizard's format picker
    /// surfaces every option without grey-outs.
    static func writer(for format: PurpleExport.DestinationFormat) throws -> PurpleExportWriter? {
        switch format {
        case .csv:      return CSVWriter()
        case .json:     return JSONWriter()
        case .markdown: return MarkdownWriter()
        case .xml:      return XMLWriter()
        case .html:     return HTMLWriter()
        case .pdf:      return PDFWriter()
        case .xlsx:     return XLSXWriter()
        case .docx:     return DOCXWriter()
        }
    }
}

// MARK: - Errors

enum PurpleExportError: LocalizedError {
    case noTypeChosen
    case typeNotFound(String)
    case formatNotSupported(PurpleExport.DestinationFormat)
    case missingCustomDestination

    var errorDescription: String? {
        switch self {
        case .noTypeChosen:
            return "Pick a target type before running the export."
        case .typeNotFound(let id):
            return "Type ‘\(id)’ no longer exists in the schema."
        case .formatNotSupported(let f):
            return "\(f.displayName) export isn't wired in this build yet."
        case .missingCustomDestination:
            return "Custom destination is selected but the path is empty."
        }
    }
}
