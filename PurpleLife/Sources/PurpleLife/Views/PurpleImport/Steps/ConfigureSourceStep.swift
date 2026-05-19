import SwiftUI

/// Step 2 — per-format options. CSV: delimiter + has-header. JSON:
/// root path + NDJSON flag. Other formats: format-specific knobs as
/// their readers land.
struct ConfigureSourceStep: View {
    @ObservedObject var model: ImportWizardModel
    @State private var delimiter: String = ","
    @State private var hasHeader: Bool = true
    @State private var rootPath: String = "$"
    @State private var ndjson: Bool = false
    @State private var markdownMode: String = "auto"
    @State private var tableIndex: Int = 0
    @State private var xlsxSheetName: String = ""
    @State private var xlsxHeaderRow: Int = 1
    @State private var xlsxStartColumn: String = ""
    @State private var xlsxEndColumn: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                switch model.draft.sourceFormat {
                case .csv:      csvSection
                case .json:     jsonSection
                case .markdown: markdownSection
                case .xml:      xmlSection
                case .xlsx:     xlsxSection
                default:        deferredSection
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 280)
            Divider()
            previewPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .onAppear {
            loadFromDraft()
            Task { await model.loadPreview() }
        }
        .onChange(of: delimiter) { persistAndReload() }
        .onChange(of: hasHeader) { persistAndReload() }
        .onChange(of: rootPath) { persistAndReload() }
        .onChange(of: ndjson) { persistAndReload() }
        .onChange(of: markdownMode) { persistAndReload() }
        .onChange(of: tableIndex) { persistAndReload() }
        .onChange(of: xlsxSheetName) { persistAndReload() }
        .onChange(of: xlsxHeaderRow) { persistAndReload() }
        .onChange(of: xlsxStartColumn) { persistAndReload() }
        .onChange(of: xlsxEndColumn) { persistAndReload() }
    }

    /// Re-renders the preview on every option change. Light debounce
    /// via the Task scheduling itself — Swift coalesces back-to-back
    /// runs when the previous Task is still pending on @MainActor.
    private func persistAndReload() {
        persist()
        Task { await model.loadPreview() }
    }

    // MARK: - Preview pane

    @ViewBuilder
    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Preview").font(.headline)
                Spacer()
                if model.pickedFilename == nil {
                    Text("Pick a file first").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 12)

            if let preview = model.preview {
                previewContent(preview)
            } else if model.pickedFilename != nil {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Reading sample…").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func previewContent(_ preview: PurpleImport.SourcePreview) -> some View {
        switch preview.shape {
        case .tabular(let columns, _):
            tabularPreview(columns: columns, rows: preview.sampleRows)
        case .tree(let paths):
            treePreview(paths: paths, rows: preview.sampleRows)
        case .document(let body):
            documentPreview(body: body)
        }
    }

    private func tabularPreview(columns: [String], rows: [PurpleImport.SourceRow]) -> some View {
        // Probe once per render — cheap, samples are at most 10 rows.
        // A column whose values are mostly integers in the Excel-date
        // window gets a date-hint treatment in the cell renderer
        // ("2019-01-13" primary, raw serial below). Gated on XLSX
        // source so a CSV column of small integers doesn't get
        // randomly reinterpreted.
        let dateLikeColumns = computeDateLikeColumns(columns: columns, rows: rows)
        return ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text("#")
                        .font(.caption.weight(.semibold)).textCase(.uppercase)
                        .tracking(0.4).foregroundStyle(.tertiary)
                        .frame(width: 32, alignment: .leading)
                        .padding(.horizontal, 6).padding(.vertical, 4)
                    ForEach(columns, id: \.self) { col in
                        HStack(spacing: 4) {
                            Text(col)
                                .font(.caption.weight(.semibold)).textCase(.uppercase)
                                .tracking(0.4).foregroundStyle(.tertiary)
                                .lineLimit(1)
                            if dateLikeColumns.contains(col) {
                                Image(systemName: "calendar")
                                    .font(.caption2)
                                    .foregroundStyle(Color.accentColor.opacity(0.7))
                                    .help("Looks like Excel-date serial numbers — map this column with Kind = Date to import as dates.")
                            }
                        }
                        .frame(width: 140, alignment: .leading)
                        .padding(.horizontal, 6).padding(.vertical, 4)
                    }
                }
                .background(Color.secondary.opacity(0.08))
                Divider()
                ForEach(Array(rows.prefix(10).enumerated()), id: \.offset) { idx, row in
                    HStack(spacing: 0) {
                        Text("\(idx + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .leading)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                        ForEach(columns, id: \.self) { col in
                            cellView(
                                raw: cellString(row.cell(at: .column(col))),
                                dateLike: dateLikeColumns.contains(col)
                            )
                        }
                    }
                    Divider().opacity(0.3)
                }
            }
        }
    }

    /// Renders one cell. For date-like XLSX columns, surfaces the
    /// converted date as the primary text and the raw serial below
    /// in a tertiary style. Otherwise a plain truncated string.
    @ViewBuilder
    private func cellView(raw: String, dateLike: Bool) -> some View {
        if dateLike, let dateStr = excelDateHint(for: raw) {
            VStack(alignment: .leading, spacing: 1) {
                Text(dateStr)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary)
                Text(raw)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 140, alignment: .leading)
            .padding(.horizontal, 6).padding(.vertical, 3)
        } else {
            Text(raw)
                .font(.caption)
                .lineLimit(1).truncationMode(.tail)
                .frame(width: 140, alignment: .leading)
                .padding(.horizontal, 6).padding(.vertical, 3)
        }
    }

    /// Per-column "is this an Excel-date-serial column?" detection.
    /// Empty when the source isn't XLSX, or when fewer than 80% of
    /// the column's non-empty values are integers in 25000..100000
    /// (roughly 1968 through 2173 — well within any realistic
    /// modern Excel date workbook).
    private func computeDateLikeColumns(columns: [String], rows: [PurpleImport.SourceRow]) -> Set<String> {
        guard model.draft.sourceFormat == .xlsx else { return [] }
        var out: Set<String> = []
        for col in columns {
            let raws = rows.compactMap { row -> String? in
                guard let v = row.cell(at: .column(col)) else { return nil }
                let s = (v as? String) ?? String(describing: v)
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            guard !raws.isEmpty else { continue }
            let serialLike = raws.filter { s in
                guard let n = Double(s) else { return false }
                return n >= 25_000 && n <= 100_000 && n == n.rounded()
            }.count
            if Double(serialLike) / Double(raws.count) >= 0.8 {
                out.insert(col)
            }
        }
        return out
    }

    /// Excel-serial → ISO-date hint. Defers to the shared coercer so
    /// the math (1899-12-30 base, leap-year quirk) stays in one
    /// place. Returns nil when the raw value isn't a serial-shaped
    /// number.
    private func excelDateHint(for raw: String) -> String? {
        guard let n = Double(raw), n >= 1, n <= 100_000 else { return nil }
        guard let date = FieldValueCoercer.asDate(raw) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func treePreview(paths: [String], rows: [PurpleImport.SourceRow]) -> some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text("#")
                        .font(.caption.weight(.semibold)).textCase(.uppercase)
                        .tracking(0.4).foregroundStyle(.tertiary)
                        .frame(width: 32, alignment: .leading)
                        .padding(.horizontal, 6).padding(.vertical, 4)
                    ForEach(paths, id: \.self) { path in
                        Text(path)
                            .font(.caption.weight(.semibold).monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .frame(width: 180, alignment: .leading)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                    }
                }
                .background(Color.secondary.opacity(0.08))
                Divider()
                ForEach(Array(rows.prefix(10).enumerated()), id: \.offset) { idx, row in
                    HStack(spacing: 0) {
                        Text("\(idx + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .leading)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                        ForEach(paths, id: \.self) { path in
                            Text(cellString(row.cell(at: .path(path))))
                                .font(.caption)
                                .lineLimit(1).truncationMode(.tail)
                                .frame(width: 180, alignment: .leading)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                        }
                    }
                    Divider().opacity(0.3)
                }
            }
        }
    }

    private func documentPreview(body: String) -> some View {
        ScrollView {
            Text(body.prefix(2000))
                .font(.caption.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(8)
                .background(Color.secondary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            if body.count > 2000 {
                Text("(\(body.count - 2000) more chars truncated)")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
    }

    private func cellString(_ value: Any?) -> String {
        guard let v = value else { return "" }
        if let s = v as? String { return s }
        if v is NSNull { return "" }
        return String(describing: v)
    }

    // MARK: - CSV

    @ViewBuilder
    private var csvSection: some View {
        Section("CSV options") {
            HStack {
                Text("Delimiter")
                Spacer()
                TextField("", text: $delimiter)
                    .frame(width: 40)
                    .multilineTextAlignment(.center)
            }
            Toggle("First row is a header", isOn: $hasHeader)
            Text("Encoding is auto-detected (UTF-8 BOM, UTF-16 BOM, Latin-1 fallback). Override via the saved mapping JSON if needed — UI surface lands in Phase 2.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - JSON

    @ViewBuilder
    private var jsonSection: some View {
        Section("JSON options") {
            HStack {
                Text("Root path")
                Spacer()
                TextField("$", text: $rootPath)
                    .frame(width: 200)
                    .multilineTextAlignment(.trailing)
            }
            Toggle("Treat as NDJSON (one object per line)", isOn: $ndjson)
            Text("Path syntax: $ = root, .key, [n], [*]. Example: $.users[*]")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Markdown

    @ViewBuilder
    private var markdownSection: some View {
        Section("Markdown options") {
            Picker("Mode", selection: $markdownMode) {
                Text("Auto-detect").tag("auto")
                Text("GFM table").tag("table")
                Text("YAML / TOML frontmatter").tag("frontmatter")
                Text("Plain document").tag("document")
            }
            .pickerStyle(.menu)
            if markdownMode == "table" || markdownMode == "auto" {
                Stepper(value: $tableIndex, in: 0...20) {
                    HStack {
                        Text("Table index")
                        Spacer()
                        Text("\(tableIndex)").foregroundStyle(.secondary)
                    }
                }
                Text("0 = first table in the file. Use higher values to pick later tables when the document has more than one.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - XML

    @ViewBuilder
    private var xmlSection: some View {
        Section("XML options") {
            HStack {
                Text("Root path")
                Spacer()
                TextField("auto", text: $rootPath)
                    .frame(width: 240)
                    .multilineTextAlignment(.trailing)
            }
            Text("Path to the element collection that fans out into one record per row. Leave blank to auto-detect the largest repeating child of the root element. Syntax: $.catalog.books[*]")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Excel (.xlsx)

    @ViewBuilder
    private var xlsxSection: some View {
        Section("Excel options") {
            // Sheet picker — populated when the file was picked.
            if model.xlsxSheetNames.isEmpty {
                HStack {
                    Text("Sheet name")
                    Spacer()
                    TextField("Sheet1", text: $xlsxSheetName)
                        .frame(width: 200)
                        .multilineTextAlignment(.trailing)
                }
                Text("Sheet list will populate once a file is picked. Type a sheet name to override.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Sheet", selection: $xlsxSheetName) {
                    Text("(first sheet)").tag("")
                    ForEach(model.xlsxSheetNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
            }

            Stepper(value: $xlsxHeaderRow, in: 0...50) {
                HStack {
                    Text("Header row")
                    Spacer()
                    Text(xlsxHeaderRow == 0 ? "none" : "\(xlsxHeaderRow)").foregroundStyle(.secondary)
                }
            }
            Text("Row number (1-based) that carries column headers. Use 0 to skip headers and address columns as col_A, col_B, …")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Text("Start column")
                Spacer()
                TextField("auto", text: $xlsxStartColumn)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("End column")
                Spacer()
                TextField("auto", text: $xlsxEndColumn)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
            }
            Text("Optional A/B/C-style column letters. Leave blank to auto-detect the populated range.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var deferredSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("Format not yet wired", systemImage: "hourglass")
                    .font(.headline)
                Text("\(model.draft.sourceFormat.displayName) readers land in a later phase. Step back and pick CSV or JSON.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Persistence

    private func loadFromDraft() {
        if case .string(let s) = model.draft.sourceOptions["delimiter"] { delimiter = s }
        if case .bool(let b) = model.draft.sourceOptions["hasHeader"] { hasHeader = b }
        if case .string(let s) = model.draft.sourceOptions["rootPath"] { rootPath = s }
        if case .bool(let b) = model.draft.sourceOptions["ndjson"] { ndjson = b }
        if case .string(let s) = model.draft.sourceOptions["mode"] { markdownMode = s }
        if case .int(let i) = model.draft.sourceOptions["tableIndex"] { tableIndex = i }
        if case .string(let s) = model.draft.sourceOptions["sheetName"] { xlsxSheetName = s }
        if case .int(let i) = model.draft.sourceOptions["headerRow"] { xlsxHeaderRow = i }
        if case .string(let s) = model.draft.sourceOptions["startColumn"] { xlsxStartColumn = s }
        if case .string(let s) = model.draft.sourceOptions["endColumn"] { xlsxEndColumn = s }
    }

    private func persist() {
        var opts = model.draft.sourceOptions
        opts["delimiter"] = .string(delimiter)
        opts["hasHeader"] = .bool(hasHeader)
        opts["rootPath"] = .string(rootPath)
        opts["ndjson"] = .bool(ndjson)
        opts["mode"] = .string(markdownMode)
        opts["tableIndex"] = .int(tableIndex)
        opts["sheetName"] = .string(xlsxSheetName)
        opts["headerRow"] = .int(xlsxHeaderRow)
        opts["startColumn"] = .string(xlsxStartColumn)
        opts["endColumn"] = .string(xlsxEndColumn)
        model.draft.sourceOptions = opts
    }
}
