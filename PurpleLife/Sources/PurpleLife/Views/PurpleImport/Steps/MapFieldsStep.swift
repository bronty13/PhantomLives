import SwiftUI

/// Step 4 — the field-mapping table. One row per source column/path
/// → target field key. Per-row: source dropdown, target field key
/// (existing or new), expected kind, transforms (collapsed for Phase
/// 1; chip-row UI in Phase 2), error behavior.
struct MapFieldsStep: View {
    @ObservedObject var model: ImportWizardModel
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Map source → field").font(.title3).bold()
                Spacer()
                Button {
                    addMapping()
                } label: {
                    Label("Add mapping", systemImage: "plus")
                }
            }
            .padding(.horizontal, 20).padding(.top, 16)

            ScrollView {
                VStack(spacing: 0) {
                    headerRow
                    Divider()
                    ForEach(Array(model.draft.fieldMappings.enumerated()), id: \.element.id) { idx, _ in
                        mappingRow(index: idx)
                        Divider()
                    }
                }
            }
            .background(Theme.bg.opacity(0.4))
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            upsertControls
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            label("Source", width: 180)
            label("Sample", width: 220)
            label("→", width: 16)
            label("Target field key", width: 180)
            label("Kind", width: 130)
            label("On error", width: 110)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
    }

    private func label(_ s: String, width: CGFloat) -> some View {
        Text(s)
            .font(.caption.weight(.semibold)).tracking(0.4)
            .textCase(.uppercase).foregroundStyle(.tertiary)
            .frame(width: width, alignment: .leading)
    }

    // MARK: - Row

    private func mappingRow(index: Int) -> some View {
        HStack(spacing: 8) {
            sourceField(index: index)
                .frame(width: 180, alignment: .leading)
            sampleValues(forMappingAt: index)
                .frame(width: 220, alignment: .leading)
            Text("→").foregroundStyle(.tertiary).frame(width: 16)
            TextField(
                "field_key",
                text: Binding(
                    get: { model.draft.fieldMappings[index].targetKey },
                    set: { model.draft.fieldMappings[index].targetKey = $0 }
                )
            )
            .font(.body.monospaced())
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)
            Picker("", selection: Binding(
                get: { model.draft.fieldMappings[index].expectedKind },
                set: { model.draft.fieldMappings[index].expectedKind = $0 }
            )) {
                ForEach(FieldKind.allCases, id: \.self) { k in
                    Text(k.displayName).tag(k)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            Picker("", selection: Binding(
                get: { model.draft.fieldMappings[index].onError },
                set: { model.draft.fieldMappings[index].onError = $0 }
            )) {
                Text("Skip row").tag(SavedImportMapping.OnError.skipRow)
                Text("Default").tag(SavedImportMapping.OnError.fillDefault)
                Text("Abort").tag(SavedImportMapping.OnError.abort)
            }
            .labelsHidden()
            .frame(width: 110)
            Spacer()
            Button {
                model.draft.fieldMappings.remove(at: index)
            } label: {
                Image(systemName: "minus.circle").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    /// Renders the first 3 sample values from the preview for this
    /// mapping's source locator. The whole point of this step is to
    /// know what column B *contains*, not just that it's column B —
    /// without this readout the user is mapping blind.
    @ViewBuilder
    private func sampleValues(forMappingAt index: Int) -> some View {
        let locator = model.draft.fieldMappings[index].source
        let samples = collectSamples(at: locator, maxCount: 3)
        if samples.isEmpty {
            Text("—")
                .font(.caption.italic())
                .foregroundStyle(.tertiary)
        } else {
            Text(samples.joined(separator: " · "))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(samples.joined(separator: "\n"))
        }
    }

    private func collectSamples(at locator: PurpleImport.SourceLocator, maxCount: Int) -> [String] {
        guard let rows = model.preview?.sampleRows else { return [] }
        var out: [String] = []
        for row in rows {
            guard let value = row.cell(at: locator) else { continue }
            let s = stringValue(value).trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { continue }
            out.append(s)
            if out.count >= maxCount { break }
        }
        return out
    }

    private func stringValue(_ v: Any) -> String {
        if let s = v as? String { return s }
        if v is NSNull { return "" }
        return String(describing: v)
    }

    @ViewBuilder
    private func sourceField(index: Int) -> some View {
        let locator = model.draft.fieldMappings[index].source
        switch locator {
        case .column(let s):
            // For tabular sources, render a menu of available columns.
            if let shape = model.preview?.shape, case let .tabular(cols, _) = shape, !cols.isEmpty {
                Picker("", selection: Binding(
                    get: { s },
                    set: { newVal in
                        model.draft.fieldMappings[index].source = .column(newVal)
                    }
                )) {
                    ForEach(cols, id: \.self) { c in Text(c).tag(c) }
                }
                .labelsHidden()
            } else {
                Text(s).font(.body.monospaced())
            }
        case .path(let p):
            // For tree sources, surface a menu of detected paths from
            // the preview plus a "Custom path…" escape hatch that
            // swaps the row to a free-form text field. Same UX shape
            // as the tabular column dropdown.
            if let shape = model.preview?.shape,
               case let .tree(paths) = shape,
               !paths.isEmpty {
                pathPicker(index: index, current: p, choices: paths)
            } else {
                TextField("$.path", text: Binding(
                    get: { p },
                    set: { model.draft.fieldMappings[index].source = .path($0) }
                ))
                .font(.body.monospaced())
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    @ViewBuilder
    private func pathPicker(index: Int, current: String, choices: [String]) -> some View {
        // If the row's current path is one of the detected ones, show
        // a compact Menu; otherwise show a TextField for free-form
        // editing with a small chevron menu next to it for switching
        // back to a detected path.
        let isCustom = !choices.contains(current)
        HStack(spacing: 4) {
            if isCustom {
                TextField("$.", text: Binding(
                    get: { current },
                    set: { model.draft.fieldMappings[index].source = .path($0) }
                ))
                .font(.body.monospaced())
                .textFieldStyle(.roundedBorder)
            } else {
                Text(current.isEmpty ? "(pick a path)" : current)
                    .font(.body.monospaced())
                    .lineLimit(1).truncationMode(.middle)
            }
            Menu {
                ForEach(choices, id: \.self) { path in
                    Button {
                        model.draft.fieldMappings[index].source = .path(path)
                    } label: {
                        HStack {
                            if path == current { Image(systemName: "checkmark") }
                            Text(path).font(.body.monospaced())
                        }
                    }
                }
                Divider()
                Button("Custom path…") {
                    // Switch to a non-detected path so the next render
                    // shows the text field.
                    if !isCustom {
                        model.draft.fieldMappings[index].source = .path("$.")
                    }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
        }
    }

    // MARK: - Upsert

    private var upsertControls: some View {
        HStack(spacing: 10) {
            Picker("Reimport behavior", selection: $model.draft.upsertStrategy) {
                Text("Insert every row").tag(SavedImportMapping.UpsertStrategy.insertOnly)
                Text("Upsert on key field").tag(SavedImportMapping.UpsertStrategy.upsertOnKey)
            }
            .pickerStyle(.menu)
            if model.draft.upsertStrategy == .upsertOnKey {
                Picker("Key field", selection: Binding(
                    get: { model.draft.keyFieldKey ?? "" },
                    set: { model.draft.keyFieldKey = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Choose…").tag("")
                    ForEach(model.draft.fieldMappings, id: \.id) { m in
                        Text(m.targetKey).tag(m.targetKey)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: - Actions

    private func addMapping() {
        let isTabular: Bool
        if case .tabular? = model.preview?.shape { isTabular = true } else { isTabular = false }
        let m = SavedImportMapping.FieldMapping(
            id: UUID().uuidString,
            source: isTabular ? .column("") : .path("$."),
            targetKey: "",
            expectedKind: .text,
            transforms: [],
            defaultValue: nil,
            onError: .skipRow
        )
        model.draft.fieldMappings.append(m)
    }
}
