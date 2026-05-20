import SwiftUI

/// Step 5 — preview the export output. Runs the chosen writer
/// against a sample of records (≤ 20) into a memory buffer and shows
/// the first ~4 KB of the rendered output. Catches mismatched
/// expectations before the user commits to writing a real file.
struct ExportPreviewStep: View {
    @ObservedObject var model: ExportWizardModel
    @EnvironmentObject private var appState: AppState

    @State private var sample: String = "(rendering…)"
    @State private var sampleBytes: Int = 0
    @State private var renderError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Preview").font(.title3).bold()
                Spacer()
                Text("\(sampleBytes) bytes (truncated to first 4 KB shown)")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            if let err = renderError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            ScrollView {
                Text(sample.prefix(4096))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.secondary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(20)
        .task(id: previewKey) { await rebuild() }
    }

    /// Re-runs when any of these change.
    private var previewKey: String {
        "\(model.draft.typeId ?? "")|\(model.draft.format.rawValue)|\(model.draft.fields.count)"
    }

    private func rebuild() async {
        // Render to a tempfile then read back — keeps the writer
        // contract clean (it takes a destination URL).
        renderError = nil
        do {
            guard let typeId = model.draft.typeId else { return }
            guard let writer = try ExportRunner.writer(for: model.draft.format) else { return }
            writer.setOptions(model.draft.formatOptions)
            let typeInfos = try model.source.listTypes()
            guard let type = typeInfos.first(where: { $0.id == typeId }) else { return }
            let allFields = try model.source.listFields(typeId: typeId)
            let selections = model.draft.fields.isEmpty
                ? allFields.map { PurpleExport.FieldSelection(id: UUID().uuidString, fieldKey: $0.key, header: $0.name) }
                : model.draft.fields
            let records = Array(
                try model.source.fetchRecords(typeId: typeId, selector: model.draft.selector).prefix(20)
            )
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("purpleexport-preview-\(UUID().uuidString).\(model.draft.format.fileExtension)")
            let bytes = try writer.write(
                type: type,
                fields: allFields,
                selections: selections,
                records: records,
                linkResolver: { model.source.resolveLinkedTitle(recordId: $0) },
                attachmentResolver: { model.source.resolveAttachmentLabel(sha256: $0) },
                to: tmp
            )
            // For binary outputs (PDF / XLSX / DOCX) the on-disk text
            // is not human-readable; show a placeholder rather than
            // dumping mojibake into the preview pane.
            switch model.draft.format {
            case .pdf:
                sample = "(PDF binary — \(bytes) bytes generated. Preview not shown here; Continue to write the actual file.)"
            case .xlsx:
                sample = "(Excel workbook — \(bytes) bytes generated. The .xlsx is a ZIP package, so preview text would be gibberish; Continue to write the actual file and open it in Excel / Numbers.)"
            case .docx:
                sample = "(Word document — \(bytes) bytes generated. The .docx is a ZIP package, so preview text would be gibberish; Continue to write the actual file and open it in Word / Pages.)"
            default:
                if let text = try? String(contentsOf: tmp, encoding: .utf8) {
                    sample = text
                } else {
                    sample = "(non-text output — \(bytes) bytes)"
                }
            }
            sampleBytes = bytes
            try? FileManager.default.removeItem(at: tmp)
        } catch {
            renderError = error.localizedDescription
            sample = ""
        }
    }
}
