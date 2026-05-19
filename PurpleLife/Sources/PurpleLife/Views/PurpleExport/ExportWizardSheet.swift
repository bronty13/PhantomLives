import SwiftUI

/// Top-level multi-step host for Purple Export. Mirror of
/// `ImportWizardSheet` shape — same `.sheet(item:)` ownership
/// pattern, same `Step` enum + terminal payload on the model, same
/// step breadcrumb + footer button arrangement.
struct ExportWizardSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var model: ExportWizardModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(minWidth: 960, minHeight: 640)
        .onAppear { model.onAppear() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.up")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Purple Export").font(.title3).bold()
                Text(stepSubtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            stepBreadcrumb
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var stepBreadcrumb: some View {
        HStack(spacing: 6) {
            ForEach(ExportStep.userVisibleSteps, id: \.self) { step in
                Circle()
                    .fill(model.step == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
    }

    private var stepSubtitle: String {
        switch model.step {
        case .pickType:    return "Step 1 of 6 — pick a type to export"
        case .pickRecords: return "Step 2 of 6 — choose which records"
        case .pickFields:  return "Step 3 of 6 — pick fields + headers"
        case .pickFormat:  return "Step 4 of 6 — pick the output format"
        case .preview:     return "Step 5 of 6 — preview"
        case .save:        return "Step 6 of 6 — destination"
        case .running:     return "Exporting…"
        case .done:        return "Done"
        case .error:       return "Failed"
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .pickType:    PickTypeStep(model: model)
        case .pickRecords: PickRecordsStep(model: model)
        case .pickFields:  PickFieldsStep(model: model)
        case .pickFormat:  PickFormatStep(model: model)
        case .preview:     ExportPreviewStep(model: model)
        case .save:        SaveStep(model: model)
        case .running:     ExportRunStep(model: model)
        case .done:        ExportDoneStep(model: model)
        case .error:       ExportErrorStep(model: model)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if model.step.canSaveConfig {
                Button("Save Config") { Task { await model.saveConfig() } }
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
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

// MARK: - Step enum

enum ExportStep: Hashable {
    case pickType
    case pickRecords
    case pickFields
    case pickFormat
    case preview
    case save
    case running
    case done
    case error

    static let userVisibleSteps: [ExportStep] = [
        .pickType, .pickRecords, .pickFields, .pickFormat, .preview, .save
    ]

    var allowsBack: Bool {
        switch self {
        case .pickType, .running, .done, .error: return false
        default: return true
        }
    }

    var nextLabel: String {
        switch self {
        case .save: return "Export"
        default:    return "Continue"
        }
    }

    var canSaveConfig: Bool {
        switch self {
        case .pickFormat, .preview, .save, .running, .done: return true
        default: return false
        }
    }
}

// MARK: - Wizard model

@MainActor
final class ExportWizardModel: ObservableObject, Identifiable {

    nonisolated let id = UUID()

    @Published var step: ExportStep = .pickType
    @Published var draft: SavedExportConfig
    @Published var summary: PurpleExport.RunSummary?
    @Published var lastError: String?

    let source: PurpleExportSource
    let configStore: ExportConfigStore
    let defaultDirectory: URL
    var runTask: Task<Void, Never>?

    init(
        draft: SavedExportConfig,
        source: PurpleExportSource,
        configStore: ExportConfigStore,
        defaultDirectory: URL
    ) {
        self.draft = draft
        self.source = source
        self.configStore = configStore
        self.defaultDirectory = defaultDirectory
    }

    func onAppear() {}

    // MARK: - Step transitions

    func next() {
        switch step {
        case .pickType:    step = .pickRecords
        case .pickRecords: step = .pickFields
        case .pickFields:  step = .pickFormat
        case .pickFormat:  step = .preview
        case .preview:     step = .save
        case .save:        step = .running; startRun()
        case .running, .done, .error: break
        }
    }

    func back() {
        switch step {
        case .pickType, .running, .done, .error: break
        case .pickRecords: step = .pickType
        case .pickFields:  step = .pickRecords
        case .pickFormat:  step = .pickFields
        case .preview:     step = .pickFormat
        case .save:        step = .preview
        }
    }

    var canAdvance: Bool {
        switch step {
        case .pickType:    return draft.typeId != nil
        case .pickRecords: return true
        case .pickFields:  return !effectiveFieldKeys.isEmpty
        case .pickFormat:
            // Phase 4 wires six writers; xlsx + docx are intentional
            // greys until Phase 4.5 / 5.
            switch draft.format {
            case .xlsx, .docx: return false
            default: return true
            }
        case .preview:     return true
        case .save:        return true
        case .running, .done, .error: return false
        }
    }

    /// Field keys actually included in the export (empty fields list
    /// means "all fields in schema order").
    var effectiveFieldKeys: [String] {
        if !draft.fields.isEmpty { return draft.fields.map(\.fieldKey) }
        guard let id = draft.typeId,
              let fs = try? source.listFields(typeId: id) else { return [] }
        return fs.map(\.key)
    }

    // MARK: - Run

    func startRun() {
        let runner = ExportRunner(
            config: draft,
            source: source,
            defaultDirectory: defaultDirectory
        )
        runTask = Task { @MainActor in
            do {
                for try await event in runner.run() {
                    self.handle(event)
                    if case .finished = event { self.step = .done; return }
                }
            } catch {
                self.lastError = error.localizedDescription
                self.step = .error
            }
        }
    }

    func cancelRun() { runTask?.cancel() }

    private func handle(_ event: PurpleExport.RunEvent) {
        switch event {
        case .willStart: break
        case .wroteFile: break
        case .finished(let s): summary = s
        case .failed(let m): lastError = m
        }
    }

    // MARK: - Persistence

    func saveConfig() async {
        do {
            let saved = try configStore.save(draft)
            self.draft = saved
        } catch {
            NSLog("PurpleLife: ExportWizardModel.saveConfig failed — \(error.localizedDescription)")
        }
    }
}
