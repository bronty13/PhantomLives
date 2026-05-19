import SwiftUI

/// Top-level multi-step host for Purple Import. Owned by the wizard
/// model below; each step view is pure (takes the model + small
/// closures). Per the plan's design decision #13, the terminal
/// summary/error live on the model, not as associated values of the
/// step enum, so `Hashable` stays trivial and step transitions are
/// cheap to compare in `withAnimation`.
struct ImportWizardSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // Parent (`ImportSettingsTab`) owns the wizard model via its
    // `@State var wizardModel: ImportWizardModel?` so the sheet
    // takes it by reference. `@StateObject` here would fight that
    // ownership — `@StateObject` is for views that mint their own
    // observable object and want to control its lifecycle. Passing
    // one in via init under `@StateObject` renders a near-empty
    // sheet on first presentation; the symptom was a tiny brown box.
    @ObservedObject var model: ImportWizardModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(minWidth: 960, minHeight: 640)
        .onAppear { model.onAppear() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Purple Import").font(.title3).bold()
                Text(stepSubtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            stepBreadcrumb
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var stepBreadcrumb: some View {
        HStack(spacing: 6) {
            ForEach(ImportStep.userVisibleSteps, id: \.self) { step in
                Circle()
                    .fill(model.step == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }

    private var stepSubtitle: String {
        switch model.step {
        case .pickSource:        return "Step 1 of 7 — pick a source file or paste data"
        case .configureSource:   return "Step 2 of 7 — configure how to read the source"
        case .pickTarget:        return "Step 3 of 7 — pick a target type"
        case .newTypeFromSource: return "Step 3a — define a new type"
        case .mapFields:         return "Step 4 of 7 — map source columns to fields"
        case .previewRows:       return "Step 5 of 7 — preview transformed rows"
        case .confirm:           return "Step 6 of 7 — confirm import"
        case .running:           return "Step 7 of 7 — importing"
        case .done:              return "Done"
        case .error:             return "Failed"
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .pickSource:        PickSourceStep(model: model)
        case .configureSource:   ConfigureSourceStep(model: model)
        case .pickTarget:        PickTargetStep(model: model)
        case .newTypeFromSource: NewTypeFromSourceStep(model: model)
        case .mapFields:         MapFieldsStep(model: model)
        case .previewRows:       PreviewRowsStep(model: model)
        case .confirm:           ConfirmStep(model: model)
        case .running:           RunStep(model: model)
        case .done:              DoneStep(model: model)
        case .error:             ErrorStep(model: model)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            // Save mapping is available from Confirm onward — once
            // the user has a meaningful spec, even if they cancel
            // the run.
            if model.step.canSaveMapping {
                Button("Save Mapping") {
                    Task { await model.saveMapping() }
                }
            }
            Spacer()
            if model.step.allowsBack {
                Button("Back") { model.back() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command])
            }
            if model.step == .done || model.step == .error {
                Button("Close") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else if model.step == .running {
                Button("Cancel") { model.cancelRun() }
            } else {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(model.step.nextLabel) { model.next() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canAdvance)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Step enum

enum ImportStep: Hashable {
    case pickSource
    case configureSource
    case pickTarget
    case newTypeFromSource
    case mapFields
    case previewRows
    case confirm
    case running
    case done
    case error

    /// Steps shown in the breadcrumb. `newTypeFromSource` is a
    /// sub-step of `pickTarget`; `done` / `error` are terminal.
    static let userVisibleSteps: [ImportStep] = [
        .pickSource, .configureSource, .pickTarget, .mapFields, .previewRows, .confirm, .running
    ]

    var allowsBack: Bool {
        switch self {
        case .pickSource, .running, .done, .error: return false
        default: return true
        }
    }

    var nextLabel: String {
        switch self {
        case .confirm: return "Import"
        default:       return "Continue"
        }
    }

    var canSaveMapping: Bool {
        switch self {
        case .confirm, .running, .done: return true
        default: return false
        }
    }
}

// MARK: - Wizard model

@MainActor
final class ImportWizardModel: ObservableObject, Identifiable {

    /// Stable id so `.sheet(item: $wizardModel)` can drive presentation.
    /// SwiftUI's `.sheet(isPresented:) + if let` pattern was flaky —
    /// some presentations rendered an empty sheet because the
    /// closure ran before the @State write had propagated. `.sheet(item:)`
    /// presents only when the binding becomes non-nil and passes the
    /// non-nil value directly, removing the timing window.
    nonisolated let id = UUID()

    @Published var step: ImportStep = .pickSource
    @Published var draft: SavedImportMapping
    @Published var preview: PurpleImport.SourcePreview?
    @Published var pickedSource: PurpleImport.SourceInput?
    @Published var pickedFilename: String?

    /// Sheet names available in the picked source. Populated when the
    /// user picks an `.xlsx` file (XLSXReader.sheetNames probes the
    /// workbook lazily); empty for non-Excel formats.
    @Published var xlsxSheetNames: [String] = []
    @Published var summary: PurpleImport.RunSummary?
    @Published var lastError: String?
    @Published var rowEvents: [PurpleImport.RunEvent] = []
    @Published var progressTotal: Int?
    @Published var progressDone: Int = 0

    let sink: PurpleImportSink
    let mappingStore: MappingStore
    var runTask: Task<Void, Never>?

    init(draft: SavedImportMapping, sink: PurpleImportSink, mappingStore: MappingStore) {
        self.draft = draft
        self.sink = sink
        self.mappingStore = mappingStore
    }

    func onAppear() {}

    // MARK: - Step transitions

    func next() {
        switch step {
        case .pickSource:        step = .configureSource
        case .configureSource:   Task { await loadPreview(); step = .pickTarget }
        case .pickTarget:        step = draft.newTypeTemplate != nil ? .newTypeFromSource : .mapFields
        case .newTypeFromSource: step = .mapFields
        case .mapFields:         step = .previewRows
        case .previewRows:       step = .confirm
        case .confirm:           step = .running; startRun()
        case .running, .done, .error: break
        }
    }

    func back() {
        switch step {
        case .pickSource, .running, .done, .error: break
        case .configureSource:   step = .pickSource
        case .pickTarget:        step = .configureSource
        case .newTypeFromSource: step = .pickTarget
        case .mapFields:         step = draft.newTypeTemplate != nil ? .newTypeFromSource : .pickTarget
        case .previewRows:       step = .mapFields
        case .confirm:           step = .previewRows
        }
    }

    /// Whether the active step is complete enough to move forward.
    var canAdvance: Bool {
        switch step {
        case .pickSource:        return pickedSource != nil
        case .configureSource:   return pickedSource != nil
        case .pickTarget:        return draft.targetTypeId != nil || draft.newTypeTemplate != nil
        case .newTypeFromSource: return draft.newTypeTemplate?.name.isEmpty == false
        case .mapFields:         return !draft.fieldMappings.isEmpty
        case .previewRows:       return true
        case .confirm:           return true
        case .running, .done, .error: return false
        }
    }

    // MARK: - Source loading

    func chooseFile(_ url: URL) {
        pickedSource = .url(url)
        pickedFilename = url.lastPathComponent
        // Detect format from the file extension if the user hasn't
        // explicitly picked one yet.
        let ext = url.pathExtension.lowercased()
        for fmt in PurpleImport.SourceFormat.allCases where fmt.defaultFileExtensions.contains(ext) {
            draft.sourceFormat = fmt
            break
        }
        // XLSX-only: probe the sheet list so the configure step's
        // sheet-name picker has options to show. Failure is
        // non-fatal — the user can still type a sheet name manually.
        if draft.sourceFormat == .xlsx, let input = pickedSource {
            xlsxSheetNames = (try? XLSXReader.sheetNames(in: input)) ?? []
        } else {
            xlsxSheetNames = []
        }
    }

    func choosePaste(_ text: String) {
        let data = Data(text.utf8)
        pickedSource = .data(data, filenameHint: "pasted.csv")
        pickedFilename = "(pasted text)"
    }

    func loadPreview() async {
        guard let source = pickedSource else { return }
        do {
            let reader = try PurpleImportReaderRegistry.reader(for: draft.sourceFormat)
            reader.setOptions(draft.sourceOptions.mapValues { (v: SourceOptionValue) in v.rawAny })
            let p = try await reader.preview(source, sampleSize: draft.previewSampleSize)
            self.preview = p
            // Seed field mappings from inferred columns + kinds on
            // first visit (only if the mapping table is still empty).
            if draft.fieldMappings.isEmpty {
                seedMappingsFromPreview(p)
            }
        } catch {
            lastError = error.localizedDescription
            step = .error
        }
    }

    private func seedMappingsFromPreview(_ preview: PurpleImport.SourcePreview) {
        switch preview.shape {
        case .tabular(let columns, let kinds):
            draft.fieldMappings = columns.map { col in
                SavedImportMapping.FieldMapping(
                    id: UUID().uuidString,
                    source: .column(col),
                    targetKey: slugify(col),
                    expectedKind: kinds[col] ?? .text,
                    transforms: [],
                    defaultValue: nil,
                    onError: .skipRow
                )
            }
        case .tree(let paths):
            draft.fieldMappings = paths.map { p in
                let name = p.split(separator: ".").last.map(String.init) ?? p
                return SavedImportMapping.FieldMapping(
                    id: UUID().uuidString,
                    source: .path(p),
                    targetKey: slugify(name),
                    expectedKind: .text,
                    transforms: [],
                    defaultValue: nil,
                    onError: .skipRow
                )
            }
        case .document:
            // v1 Word/PDF — single record, single body field.
            draft.fieldMappings = []
        }
    }

    private func slugify(_ s: String) -> String {
        var out = ""
        var lastWasSep = true
        for c in s.lowercased() {
            if c.isLetter || c.isNumber {
                out.append(c)
                lastWasSep = false
            } else if !lastWasSep {
                out.append("_")
                lastWasSep = true
            }
        }
        if out.hasSuffix("_") { out.removeLast() }
        return out.isEmpty ? "field" : out
    }

    // MARK: - Run

    func startRun() {
        guard let source = pickedSource else { return }
        do {
            let reader = try PurpleImportReaderRegistry.reader(for: draft.sourceFormat)
            let runner = ImportRunner(mapping: draft, reader: reader, sink: sink, source: source)
            runTask = Task { @MainActor in
                do {
                    for try await event in runner.run() {
                        self.handleEvent(event)
                        if case .finished = event {
                            self.step = .done
                            return
                        }
                    }
                } catch {
                    self.lastError = error.localizedDescription
                    self.step = .error
                }
            }
        } catch {
            self.lastError = error.localizedDescription
            self.step = .error
        }
    }

    func cancelRun() {
        runTask?.cancel()
    }

    private func handleEvent(_ event: PurpleImport.RunEvent) {
        rowEvents.append(event)
        switch event {
        case .willStart(let total):
            progressTotal = total
            progressDone = 0
        case .row:
            progressDone += 1
        case .finished(let s):
            summary = s
        case .failed(let msg):
            lastError = msg
        }
    }

    // MARK: - Persistence

    func saveMapping() async {
        do {
            let saved = try mappingStore.save(draft)
            self.draft = saved
        } catch {
            NSLog("PurpleLife: saveMapping failed — \(error.localizedDescription)")
        }
    }
}
