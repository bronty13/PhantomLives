import SwiftUI
import UniformTypeIdentifiers

struct ImportWizardView: View {
    @EnvironmentObject private var appState: AppState

    enum Stage {
        case source
        case sheets         // xlsx only
        case mapping        // pick a single sheet to commit to clips
        case preview
        case done
    }

    @State private var stage: Stage = .source

    // Input
    @State private var pickedURL: URL?
    @State private var pasted: String = ""
    @State private var sourceLabel: String = ""

    // XLSX
    @State private var loadedSheets: [XLSXReader.Sheet] = []
    @State private var sheetSpecs: [ImportSheetSpec] = []
    @State private var selectedSheetForClips: String = ""

    // Active sheet → mapping
    @State private var activeSheetName: String = ""
    @State private var sourceColumns: [String] = []
    @State private var dataRows: [[String]] = []
    @State private var mapping: [Int: ClipFieldKey] = [:]

    // Outcomes
    @State private var clipsResult: ImportService.ClipsCommitResult?
    @State private var calendarResult: ImportService.CalendarCommitResult?
    @State private var error: String?
    @State private var loading: Bool = false
    @State private var markAsHistorical: Bool = false

    var body: some View {
        EdPageShell(
            eyebrow: "Section · Import",
            headline: "Pull a sheet in.",
            emphasized: "in",
            deck: "Five steps: source → sheets → mapping → preview → commit.",
            trailing: AnyView(
                Button { reset() } label: { Text("RESET") }
                    .buttonStyle(EdGhostButtonStyle())
            )
        ) {
            VStack(spacing: 0) {
                stepIndicator
                EdHairline(color: EdColor.ink(0.18))
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .importRequested)) { _ in
            reset()
        }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 14) {
            stepLabel("1. Source",   active: stage == .source)
            chevron
            stepLabel("2. Sheets",   active: stage == .sheets,
                      enabled: pickedURL != nil)
            chevron
            stepLabel("3. Mapping",  active: stage == .mapping,
                      enabled: !sourceColumns.isEmpty)
            chevron
            stepLabel("4. Preview",  active: stage == .preview,
                      enabled: !mapping.isEmpty)
            chevron
            stepLabel("5. Commit",   active: stage == .done)
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(EdColor.bone)
    }

    @ViewBuilder
    private func stepLabel(_ title: String, active: Bool, enabled: Bool = true) -> some View {
        let foreground: Color = active ? EdColor.ink : (enabled ? EdColor.ink(0.6) : EdColor.ink(0.35))
        Text(title.uppercased())
            .font(EdFont.mono(11, weight: active ? .semibold : .regular))
            .tracking(0.84)
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(active ? EdColor.acid : Color.clear)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(EdFont.mono(11))
            .foregroundStyle(EdColor.ink(0.35))
    }

    // MARK: - Content router

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .source:   sourceStep
        case .sheets:   sheetsStep
        case .mapping:  mappingStep
        case .preview:  previewStep
        case .done:     doneStep
        }
    }

    // MARK: - Step 1 — Source

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pick a file to import")
                .font(.title3.weight(.semibold))
            Text("Supports .xlsx (sheet routing), .csv, .tsv, or pasted text below.")
                .font(.callout).foregroundStyle(.secondary)

            HStack {
                Button {
                    pickFile()
                } label: {
                    Label("Choose file…", systemImage: "doc")
                }
                .keyboardShortcut(.defaultAction)

                if let url = pickedURL {
                    Text(url.lastPathComponent)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Divider().padding(.vertical, 8)

            Text("Or paste tabular text")
                .font(.headline)

            TextEditor(text: $pasted)
                .font(.body.monospaced())
                .frame(minHeight: 180)
                .border(.separator)

            HStack {
                if let error = error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Spacer()
                Button("Continue") { advanceFromSource() }
                    .buttonStyle(.borderedProminent)
                    .disabled(pickedURL == nil && pasted.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    // MARK: - Step 2 — Sheets (xlsx only)

    private var sheetsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Pick what to import")
                    .font(.title3.weight(.semibold))

                clipsRecommendation

                otherSheetsCard

                if let error { Text(error).font(.caption).foregroundStyle(.red) }

                Spacer().frame(height: 4)

                Text("What do these targets mean?")
                    .font(.headline)
                targetLegend
            }
            .padding(20)
        }
    }

    // MARK: Recommended hero card (clip sheets)

    @ViewBuilder
    private var clipsRecommendation: some View {
        let clipSheets = sheetSpecs.filter { $0.target == .clips }
        if clipSheets.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("No sheet was auto-routed to Clips", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.headline)
                Text("Use the table below to mark whichever sheet holds your clip rows as Target = Clips, then come back here.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("Your master clip list", systemImage: "star.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tint)
                ForEach(clipSheets) { spec in
                    clipSheetCard(spec)
                }
            }
        }
    }

    private func clipSheetCard(_ spec: ImportSheetSpec) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(spec.sheetName)
                    .font(.title2.weight(.semibold))
                Text("·").foregroundStyle(.tertiary)
                Text("\(spec.rowCount) rows · \(spec.columnCount) cols")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text("Map columns once, preview a few rows, then commit. Tick \"Treat as historical\" on the preview step if these clips were already published — that auto-marks every persona-scope site as posted and lands them in **Production** status.")
                .font(.callout).foregroundStyle(.secondary)

            Button {
                activeSheetName = spec.sheetName
                advanceToMapping()
            } label: {
                Label("Continue with \"\(spec.sheetName)\" → Mapping", systemImage: "arrow.right.circle.fill")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.tint, lineWidth: 1))
    }

    // MARK: Other-sheets routing

    private var otherSheetsCard: some View {
        let nonClipSheets = sheetSpecs.filter { $0.target != .clips }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Other sheets — auto-routed (review and skip / change as needed)")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(nonClipSheets) { spec in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(spec.sheetName).font(.body.weight(.medium))
                            Text("\(spec.rowCount) rows")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Picker("", selection: targetBinding(for: spec)) {
                            ForEach(ImportTarget.allCases, id: \.self) { t in
                                Text(t.label).tag(t)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    Divider()
                }
            }
            .background(EdColor.bone)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 1))

            HStack(spacing: 10) {
                Button {
                    commitNonClipSheets()
                } label: {
                    Label("Commit Calendar / Posting / Price sheets now", systemImage: "checkmark.circle")
                }
                .help("Runs every non-clip sheet (Calendar Events, Posting Backfill, Prices) through the importer immediately. Doesn't touch the master clip list.")

                if let cal = calendarResult {
                    Text("Calendar: +\(cal.inserted) new, \(cal.updated) updated, \(cal.skipped) skipped")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: Target legend

    private var targetLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            legendRow(target: .clips,
                      desc: "Insert as new clips. The big load — your master clip list goes here.")
            legendRow(target: .calendarEvents,
                      desc: "Backfill `(date, persona)` calendar events from a row-per-date scheduler sheet.")
            legendRow(target: .clipPostings,
                      desc: "Set per-clip / per-site posting status from a sheet with site-done columns. Optional — \"historical\" toggle in step 4 covers most cases.")
            legendRow(target: .prices,
                      desc: "Reference price entries (used by reports and exports).")
            legendRow(target: .skip,
                      desc: "Don't import this sheet.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func legendRow(target: ImportTarget, desc: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(target.label)
                .frame(width: 130, alignment: .leading)
                .foregroundStyle(.primary)
            Text(desc).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var canAdvanceToMapping: Bool {
        guard let spec = sheetSpecs.first(where: { $0.sheetName == activeSheetName }) else { return false }
        return spec.target == .clips
    }

    private func targetBinding(for spec: ImportSheetSpec) -> Binding<ImportTarget> {
        Binding(
            get: {
                sheetSpecs.first(where: { $0.sheetName == spec.sheetName })?.target ?? .skip
            },
            set: { newVal in
                if let idx = sheetSpecs.firstIndex(where: { $0.sheetName == spec.sheetName }) {
                    sheetSpecs[idx].target = newVal
                }
            }
        )
    }

    // MARK: - Step 3 — Mapping

    private var mappingStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Map each source column to a target field")
                .font(.title3.weight(.semibold))
            Text("Auto-suggested by fuzzy match — review and adjust. Set columns you don't need to \"— ignore —\".")
                .font(.callout).foregroundStyle(.secondary)

            mappingList
                .frame(maxHeight: .infinity)

            HStack {
                Button("Back") { stage = pickedURL != nil ? .sheets : .source }
                Spacer()
                Button("Continue → Preview") { stage = .preview }
                    .buttonStyle(.borderedProminent)
                    .disabled(mapping.values.allSatisfy { $0 == .ignore })
            }
        }
        .padding(20)
    }

    private var mappingList: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Text("Source column").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Sample").frame(maxWidth: .infinity, alignment: .leading)
                    Text("→ Field").frame(width: 280, alignment: .leading)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                Divider()
                ForEach(0..<sourceColumns.count, id: \.self) { idx in
                    mappingRow(idx: idx)
                    Divider()
                }
            }
        }
        .background(EdColor.bone)
        .border(.separator)
    }

    private func mappingRow(idx: Int) -> some View {
        HStack {
            Text(sourceColumns[idx].isEmpty ? "(col \(idx + 1))" : sourceColumns[idx])
                .font(.body.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            Text(sample(forColumn: idx))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("", selection: mappingBinding(for: idx)) {
                ForEach(ClipFieldKey.allCases, id: \.self) { key in
                    Text(key.label).tag(key)
                }
            }
            .labelsHidden()
            .frame(width: 280)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
    }

    private func mappingBinding(for idx: Int) -> Binding<ClipFieldKey> {
        Binding(
            get: { mapping[idx] ?? .ignore },
            set: { mapping[idx] = $0 }
        )
    }

    private func sample(forColumn idx: Int) -> String {
        for row in dataRows.prefix(20) {
            if idx < row.count, !row[idx].isEmpty {
                return row[idx]
            }
        }
        return "—"
    }

    // MARK: - Step 4 — Preview

    private var previewStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview — first 30 rows")
                .font(.title3.weight(.semibold))
            Text("Showing only mapped columns. \(dataRows.count) data rows total.")
                .font(.callout).foregroundStyle(.secondary)

            previewTable

            historicalToggle

            HStack {
                Button("Back") { stage = .mapping }
                Spacer()
                Button(commitButtonLabel) { commitClips() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }

    private var commitButtonLabel: String {
        markAsHistorical
            ? "Commit \(dataRows.count) rows as historical (Production)"
            : "Commit \(dataRows.count) rows"
    }

    private var historicalToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $markAsHistorical) {
                Text("Treat as historical (mark all persona-scope sites as already posted)")
                    .font(.callout.weight(.medium))
            }
            .toggleStyle(.checkbox)
            Text("Use this when importing previously-published clips. For each imported clip, every site in its persona's scope (e.g. CoC → c4s+mv+nf) is upserted as `posted` with the clip's go-live date (or content date, or today) as the posting date. Status auto-advances to “Production”. Subsequent re-imports of the same clip will not double-post.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var previewTable: some View {
        let columns = mappedColumns
        let visibleRows = Array(dataRows.prefix(30).enumerated())

        return ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    ForEach(columns, id: \.self) { idx in
                        Text(headerLabel(forColumnIndex: idx))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 80, idealWidth: 160, maxWidth: 240, alignment: .leading)
                    }
                }
                Divider()
                ForEach(visibleRows, id: \.offset) { _, row in
                    HStack(spacing: 12) {
                        ForEach(columns, id: \.self) { colIdx in
                            Text(colIdx < row.count ? row[colIdx] : "")
                                .font(.caption)
                                .lineLimit(2)
                                .frame(minWidth: 80, idealWidth: 160, maxWidth: 240, alignment: .leading)
                        }
                    }
                }
            }
            .padding(8)
        }
        .frame(maxHeight: .infinity)
        .background(EdColor.bone)
        .border(.separator)
    }

    private var mappedColumns: [Int] {
        mapping.compactMap { (idx, key) in key == .ignore ? nil : idx }.sorted()
    }

    private func headerLabel(forColumnIndex idx: Int) -> String {
        guard let key = mapping[idx], key != .ignore else { return sourceColumns[idx] }
        return "\(key.label)"
    }

    // MARK: - Step 5 — Done

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.green)
            Text("Import complete")
                .font(.title.weight(.semibold))

            if let r = clipsResult {
                VStack(spacing: 4) {
                    Text("Clips: +\(r.inserted) inserted, \(r.skippedDuplicates) duplicates skipped, \(r.failed) failed")
                    if r.historicalMarked > 0 {
                        Text("\(r.historicalMarked) clip(s) marked as historical → Production")
                            .foregroundStyle(.green)
                    }
                    if !r.errors.isEmpty {
                        DisclosureGroup("\(r.errors.count) error(s)") {
                            ScrollView {
                                ForEach(r.errors, id: \.self) { e in
                                    Text(e).font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .frame(maxHeight: 200)
                        }
                    }
                }
                .padding()
            }
            if let r = calendarResult {
                Text("Calendar Events: +\(r.inserted) new, ~\(r.updated) updated, \(r.skipped) skipped, \(r.failed) failed")
                    .padding()
            }

            Button("Start over") { reset() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Actions

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType.spreadsheet,
            UTType(filenameExtension: "xlsx") ?? UTType.data,
            UTType.commaSeparatedText,
            UTType.tabSeparatedText,
            UTType.plainText,
        ]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            pickedURL = url
            sourceLabel = url.lastPathComponent
        }
    }

    private func advanceFromSource() {
        error = nil
        if let url = pickedURL {
            switch ImportService.detect(url: url) {
            case .xlsx:
                loadXLSX(url: url)
            case .csv:
                loadDelimited(text: (try? String(contentsOf: url, encoding: .utf8)) ?? "", separator: ",")
                stage = .mapping
            case .tsv:
                loadDelimited(text: (try? String(contentsOf: url, encoding: .utf8)) ?? "", separator: "\t")
                stage = .mapping
            case .text:
                loadDelimited(text: (try? String(contentsOf: url, encoding: .utf8)) ?? "",
                              separator: ImportService.detectDelimiter(text: pasted))
                stage = .mapping
            }
        } else if !pasted.isEmpty {
            let delim = ImportService.detectDelimiter(text: pasted)
            loadDelimited(text: pasted, separator: delim)
            stage = .mapping
        }
    }

    private func loadXLSX(url: URL) {
        loading = true
        defer { loading = false }
        do {
            let sheets = try ImportService.loadSheets(url: url)
            loadedSheets = sheets
            sheetSpecs   = ImportService.suggestRouting(for: sheets)
            // Default selection: the first sheet routed to Clips
            if let firstClip = sheetSpecs.first(where: { $0.target == .clips }) {
                activeSheetName = firstClip.sheetName
            }
            stage = .sheets
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadDelimited(text: String, separator: Character) {
        let rows = ImportService.parseDelimited(text: text, separator: separator)
        let extracted = ImportService.extractHeader(from: rows)
        sourceColumns = extracted.headers
        dataRows = extracted.dataRows
        autosuggestMapping()
    }

    private func advanceToMapping() {
        guard let spec = sheetSpecs.first(where: { $0.sheetName == activeSheetName }),
              let sheet = loadedSheets.first(where: { $0.name == spec.sheetName })
        else {
            error = "Pick a sheet whose target is Clips."
            return
        }
        let extracted = ImportService.extractHeader(from: sheet.rows)
        sourceColumns = extracted.headers
        dataRows = extracted.dataRows
        autosuggestMapping()
        stage = .mapping
    }

    private func autosuggestMapping() {
        var m: [Int: ClipFieldKey] = [:]
        for (idx, header) in sourceColumns.enumerated() {
            m[idx] = FuzzyMatch.suggest(column: header) ?? .ignore
        }
        mapping = m
    }

    private func commitNonClipSheets() {
        var calResult: ImportService.CalendarCommitResult?
        for spec in sheetSpecs {
            guard let sheet = loadedSheets.first(where: { $0.name == spec.sheetName }) else { continue }
            switch spec.target {
            case .calendarEvents:
                let extracted = ImportService.extractHeader(from: sheet.rows)
                let r = ImportService.commitCalendarEvents(
                    rows: extracted.dataRows,
                    mapping: [:],
                    sourceColumns: extracted.headers,
                    appState: appState
                )
                if calResult == nil { calResult = r }
                else {
                    var merged = calResult!
                    merged.inserted += r.inserted
                    merged.updated  += r.updated
                    merged.skipped  += r.skipped
                    merged.failed   += r.failed
                    calResult = merged
                }
            default:
                break
            }
        }
        calendarResult = calResult
    }

    private func commitClips() {
        let result = ImportService.commitClips(
            rows: dataRows,
            mapping: mapping,
            appState: appState,
            duplicateStrategy: appState.settings.importDuplicateStrategy,
            markAllAsHistorical: markAsHistorical
        )
        clipsResult = result
        stage = .done
    }

    private func reset() {
        stage = .source
        pickedURL = nil
        pasted = ""
        sourceLabel = ""
        loadedSheets = []
        sheetSpecs = []
        selectedSheetForClips = ""
        activeSheetName = ""
        sourceColumns = []
        dataRows = []
        mapping = [:]
        clipsResult = nil
        calendarResult = nil
        error = nil
    }
}
