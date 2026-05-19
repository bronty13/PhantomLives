import SwiftUI

/// Step 5 — preview transformed rows. Shows the first N rows
/// after running the source through the field mappings + coercer,
/// flagging any per-cell failures so the user can fix mappings
/// before the run.
struct PreviewRowsStep: View {
    @ObservedObject var model: ImportWizardModel

    @State private var previewOutcomes: [PreviewedRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview").font(.title3).bold()
                .padding(.horizontal, 20).padding(.top, 16)
            Text(summaryLine)
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                    Divider()
                    ForEach(previewOutcomes.indices, id: \.self) { i in
                        rowView(previewOutcomes[i])
                        Divider()
                    }
                }
            }
            .background(Theme.bg.opacity(0.4))
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
        .onAppear { rebuild() }
    }

    // MARK: - Rebuild

    private struct PreviewedRow: Identifiable {
        let id = UUID()
        let index: Int
        let outcome: ImportRunner.RowOutcome
    }

    private func rebuild() {
        guard let preview = model.preview else { previewOutcomes = []; return }
        // Synthesize a runner just to use its row-coercer logic. The
        // sink + source are unused for the preview pass; we hand
        // empty placeholders that we never call into.
        var rows: [PreviewedRow] = []
        let mappings = model.draft.fieldMappings
        let fieldOptions: [String: [FieldOption]] = [:]
        for (idx, row) in preview.sampleRows.enumerated() {
            let outcome = coercePreviewRow(row, mappings: mappings, fieldOptions: fieldOptions)
            rows.append(PreviewedRow(index: idx, outcome: outcome))
        }
        previewOutcomes = rows
    }

    /// Stand-in for `ImportRunner.coerceRow` that the preview can
    /// call without instantiating a full runner. Behavior must stay
    /// in lockstep with the real one — Phase 2 likely refactors both
    /// to call a shared free function on `FieldValueCoercer`.
    private func coercePreviewRow(
        _ row: PurpleImport.SourceRow,
        mappings: [SavedImportMapping.FieldMapping],
        fieldOptions: [String: [FieldOption]]
    ) -> ImportRunner.RowOutcome {
        var values: [String: Any] = [:]
        for m in mappings {
            let raw = row.cell(at: m.source)
            switch FieldValueCoercer.coerce(raw, to: m.expectedKind, fieldOptions: fieldOptions[m.targetKey] ?? []) {
            case .value(let v):
                values[m.targetKey] = v
            case .empty:
                switch m.onError {
                case .skipRow:     return .skipped(reason: "empty: \(m.targetKey)")
                case .fillDefault: if let d = m.defaultValue { values[m.targetKey] = d.rawAny }
                case .abort:       return .failed(reason: "empty: \(m.targetKey) aborted")
                }
            case .failure(let err):
                switch m.onError {
                case .skipRow:     return .skipped(reason: err.description)
                case .fillDefault: if let d = m.defaultValue { values[m.targetKey] = d.rawAny }
                case .abort:       return .failed(reason: err.description)
                }
            }
        }
        return .accepted(values)
    }

    // MARK: - Render

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("Row").frame(width: 36, alignment: .leading)
            Text("Status").frame(width: 96, alignment: .leading)
            ForEach(model.draft.fieldMappings, id: \.id) { m in
                Text(m.targetKey).frame(width: 140, alignment: .leading)
            }
        }
        .font(.caption.weight(.semibold)).tracking(0.4).textCase(.uppercase)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
    }

    private func rowView(_ p: PreviewedRow) -> some View {
        HStack(spacing: 8) {
            Text(String(p.index + 1)).font(.body.monospacedDigit())
                .frame(width: 36, alignment: .leading).foregroundStyle(.secondary)
            statusBadge(p.outcome).frame(width: 96, alignment: .leading)
            ForEach(model.draft.fieldMappings, id: \.id) { m in
                Text(cellValue(p.outcome, key: m.targetKey))
                    .font(.body)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(width: 140, alignment: .leading)
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func statusBadge(_ outcome: ImportRunner.RowOutcome) -> some View {
        switch outcome {
        case .accepted:
            return AnyView(Label("OK", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption))
        case .skipped(let r):
            return AnyView(Label("Skip", systemImage: "arrow.right.circle").foregroundStyle(.orange).font(.caption).help(r))
        case .failed(let r):
            return AnyView(Label("Fail", systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.caption).help(r))
        }
    }

    private func cellValue(_ outcome: ImportRunner.RowOutcome, key: String) -> String {
        if case .accepted(let dict) = outcome, let v = dict[key] {
            return String(describing: v)
        }
        return "—"
    }

    private var summaryLine: String {
        let total = previewOutcomes.count
        let ok = previewOutcomes.filter { if case .accepted = $0.outcome { return true }; return false }.count
        let skip = previewOutcomes.filter { if case .skipped = $0.outcome { return true }; return false }.count
        let fail = previewOutcomes.filter { if case .failed = $0.outcome { return true }; return false }.count
        return "Sample: \(total) rows — \(ok) OK, \(skip) skipped, \(fail) failed. (Full run will process every row in the source.)"
    }
}
