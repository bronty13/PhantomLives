import SwiftUI
import AppKit

/// Workflow Chains management + run sheet (Kyno-parity row 66).
///
/// Two panes side-by-side: chain list on the left (add / rename /
/// delete / reorder), the selected chain's step editor on the
/// right. Bottom bar runs the selected chain against a user-picked
/// source folder and surfaces step-level progress.
///
/// MVP scope: three step kinds (Verified Backup, Transcode, Export
/// Report). Re-ordering steps within a chain via up/down arrows;
/// drag-and-drop is a follow-up. Auto-trigger on camera-media
/// mount is wired through the `runOnCameraMediaMount` chain flag
/// (handled in `VolumeWatcher`).
struct WorkflowChainsSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var chains: [WorkflowChain] = []
    @State private var selectedID: UUID?
    @State private var sourceFolder: URL?
    @State private var activeRun: WorkflowChainRun?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                chainList
                    .frame(width: 220)
                Divider()
                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(width: 860, height: 600)
        .onAppear { chains = WorkflowChainsStore.load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.right.arrow.left.square")
                .font(.title3)
                .foregroundStyle(.tint)
            Text("Workflow Chains")
                .font(.title3.weight(.semibold))
            Text("offload → transcode → report, as one job")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    // MARK: - Chain list

    private var chainList: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(chains) { chain in
                    HStack {
                        Image(systemName: chain.runOnCameraMediaMount
                              ? "sd.card.fill" : "sd.card")
                            .foregroundStyle(chain.runOnCameraMediaMount
                                              ? Color.orange : .secondary)
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(chain.name)
                                .lineLimit(1)
                            Text("\(chain.steps.count) step(s)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(chain.id)
                }
            }
            HStack(spacing: 4) {
                Button { addChain() } label: { Image(systemName: "plus") }
                Button { deleteSelected() } label: { Image(systemName: "minus") }
                    .disabled(selectedID == nil)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Detail (step editor)

    @ViewBuilder
    private var detailPane: some View {
        if let idx = selectedIndex {
            ChainEditor(
                chain: Binding(
                    get: { chains[idx] },
                    set: { chains[idx] = $0; saveChains() }
                )
            )
            .padding(12)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "arrow.right.arrow.left.square")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Select a chain on the left, or click + to create one.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Footer (run controls + progress)

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Run on:")
                    .foregroundStyle(.secondary)
                Text(sourceFolder?.path ?? "—")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(sourceFolder == nil ? .secondary : .primary)
                Spacer()
                Button("Choose Folder…") { pickSource() }
                Button("Run Chain") { runSelected() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRun)
            }
            if let run = activeRun {
                runProgress(run)
            }
        }
        .padding(12)
    }

    private func runProgress(_ run: WorkflowChainRun) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Run: \(run.chain.name)")
                    .font(.caption.weight(.semibold))
                Spacer()
                if !run.state.isTerminal {
                    Button("Cancel") { run.cancel() }
                        .controlSize(.small)
                }
            }
            ForEach(run.steps) { stepState in
                HStack(spacing: 6) {
                    Image(systemName: iconFor(state: stepState.status))
                        .foregroundStyle(colorFor(state: stepState.status))
                        .frame(width: 16)
                    Text(stepState.step.displayName)
                        .font(.caption)
                    Spacer()
                    Text(stepState.detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if !run.artifacts.isEmpty,
               run.state == .finished {
                Button("Reveal Artifacts in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(run.artifacts)
                }
                .controlSize(.small)
            }
        }
    }

    private func iconFor(state: WorkflowChainRun.State) -> String {
        switch state {
        case .queued:    return "circle"
        case .running:   return "arrow.triangle.2.circlepath"
        case .finished:  return "checkmark.circle.fill"
        case .failed:    return "xmark.octagon.fill"
        case .cancelled: return "exclamationmark.circle"
        }
    }
    private func colorFor(state: WorkflowChainRun.State) -> Color {
        switch state {
        case .queued:    return .secondary
        case .running:   return .orange
        case .finished:  return .green
        case .failed:    return .red
        case .cancelled: return .secondary
        }
    }

    // MARK: - Actions

    private var canRun: Bool {
        guard let idx = selectedIndex else { return false }
        return sourceFolder != nil
            && !chains[idx].steps.isEmpty
            && activeRun?.state.isTerminal != false
    }

    private var selectedIndex: Int? {
        guard let id = selectedID else { return nil }
        return chains.firstIndex { $0.id == id }
    }

    private func addChain() {
        let chain = WorkflowChain(
            name: "Untitled Chain",
            steps: [.verifiedBackup(.defaults)]
        )
        chains.append(chain)
        selectedID = chain.id
        saveChains()
    }

    private func deleteSelected() {
        guard let id = selectedID else { return }
        chains.removeAll { $0.id == id }
        selectedID = nil
        saveChains()
    }

    private func saveChains() {
        WorkflowChainsStore.save(chains)
    }

    private func pickSource() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { sourceFolder = panel.url }
    }

    private func runSelected() {
        guard let idx = selectedIndex,
              let source = sourceFolder else { return }
        if let err = WorkflowChainsService.validate(chains[idx]) {
            let alert = NSAlert()
            alert.messageText = "Can't run this chain"
            alert.informativeText = err
            alert.runModal()
            return
        }
        let run = WorkflowChainRun(chain: chains[idx], source: source)
        activeRun = run
        Task {
            await run.run(
                toolVersion: AppVersion.marketing,
                transcodeQueue: appState.transcodeQueue,
                appState: appState
            )
        }
    }
}

// MARK: - Step editor

private struct ChainEditor: View {
    @Binding var chain: WorkflowChain

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                topRow
                Divider()
                stepsList
                Divider()
                addStepButtons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var topRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Name:")
                    .frame(width: 80, alignment: .trailing)
                    .foregroundStyle(.secondary)
                TextField("", text: $chain.name)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(alignment: .top) {
                Text("Notes:")
                    .frame(width: 80, alignment: .trailing)
                    .foregroundStyle(.secondary)
                TextEditor(text: $chain.notes)
                    .frame(height: 44)
                    .border(Color.secondary.opacity(0.3))
            }
            Toggle("Offer to run automatically when a camera card mounts",
                   isOn: $chain.runOnCameraMediaMount)
                .padding(.leading, 84)
        }
    }

    private var stepsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Steps")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(chain.steps.enumerated()), id: \.offset) { idx, _ in
                StepRow(
                    index: idx,
                    step: Binding(
                        get: { chain.steps[idx] },
                        set: { chain.steps[idx] = $0 }
                    ),
                    onMoveUp: { move(idx, by: -1) },
                    onMoveDown: { move(idx, by: 1) },
                    onDelete: { chain.steps.remove(at: idx) },
                    canMoveUp: idx > 0,
                    canMoveDown: idx < chain.steps.count - 1
                )
            }
            if chain.steps.isEmpty {
                Text("No steps yet — add one below.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
    }

    private var addStepButtons: some View {
        HStack(spacing: 8) {
            Text("Add step:")
                .foregroundStyle(.secondary)
            Button("Verified Backup") {
                chain.steps.append(.verifiedBackup(.defaults))
            }
            Button("Transcode") {
                chain.steps.append(.transcode(.defaults))
            }
            Button("Export Report") {
                chain.steps.append(.exportReport(.defaults))
            }
            Spacer()
        }
    }

    private func move(_ index: Int, by delta: Int) {
        let target = index + delta
        guard target >= 0, target < chain.steps.count else { return }
        chain.steps.swapAt(index, target)
    }
}

// MARK: - Step row

private struct StepRow: View {
    let index: Int
    @Binding var step: WorkflowChain.Step
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("\(index + 1).")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Image(systemName: step.icon)
                    .foregroundStyle(.tint)
                    .frame(width: 18)
                Text(step.displayName).font(.callout.weight(.semibold))
                Spacer()
                Button { onMoveUp() } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(.borderless).disabled(!canMoveUp)
                Button { onMoveDown() } label: { Image(systemName: "arrow.down") }
                    .buttonStyle(.borderless).disabled(!canMoveDown)
                Button { onDelete() } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.borderless)
            }
            stepEditor
                .padding(.leading, 32)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    @ViewBuilder
    private var stepEditor: some View {
        switch step {
        case .verifiedBackup(let p):
            BackupStepEditor(
                params: Binding(
                    get: { p },
                    set: { step = .verifiedBackup($0) }
                )
            )
        case .transcode(let p):
            TranscodeStepEditor(
                params: Binding(
                    get: { p },
                    set: { step = .transcode($0) }
                )
            )
        case .exportReport(let p):
            ReportStepEditor(
                params: Binding(
                    get: { p },
                    set: { step = .exportReport($0) }
                )
            )
        }
    }
}

// MARK: - Per-step editors

private struct BackupStepEditor: View {
    @Binding var params: WorkflowChain.VerifiedBackupParams
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Hash:").frame(width: 80, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Picker("", selection: $params.hashAlgorithm) {
                    ForEach(HashAlgorithm.allCases) { a in
                        Text(a.rawValue).tag(a.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
                Picker("", selection: $params.mhlFormat) {
                    ForEach(MHLFormat.allCases) { f in
                        Text(f.rawValue).tag(f.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
                Spacer()
            }
            HStack(alignment: .top) {
                Text("Destinations:")
                    .frame(width: 80, alignment: .trailing)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(params.destinationPaths.enumerated()),
                            id: \.offset) { idx, path in
                        HStack {
                            Text(path).font(.caption.monospaced())
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { params.destinationPaths.remove(at: idx) }
                                label: { Image(systemName: "xmark.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button("Add Destination…") { pickDestination() }
                        .controlSize(.small)
                }
            }
        }
    }
    private func pickDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            params.destinationPaths.append(url.path)
        }
    }
}

private struct TranscodeStepEditor: View {
    @Binding var params: WorkflowChain.TranscodeParams
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Preset:").frame(width: 80, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Picker("", selection: $params.presetID) {
                    ForEach(TranscodePreset.all.filter { !$0.isFFmpeg },
                            id: \.id) { p in
                        Text(p.name).tag(p.id)
                    }
                }
                .labelsHidden()
            }
            HStack {
                Text("Output:").frame(width: 80, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Text(params.outputPath.isEmpty
                     ? "<source>/Proxies/  (default)"
                     : params.outputPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose…") { pickOutput() }
                    .controlSize(.small)
                if !params.outputPath.isEmpty {
                    Button("Reset") { params.outputPath = "" }
                        .controlSize(.small)
                }
            }
        }
    }
    private func pickOutput() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            params.outputPath = url.path
        }
    }
}

private struct ReportStepEditor: View {
    @Binding var params: WorkflowChain.ReportParams
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Format:").frame(width: 80, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Picker("", selection: $params.format) {
                    Text("HTML (with thumbnails)").tag("html")
                    Text("CSV").tag("csv")
                }
                .labelsHidden()
                .frame(width: 220)
                Spacer()
            }
            HStack {
                Text("Output:").frame(width: 80, alignment: .trailing)
                    .foregroundStyle(.secondary)
                Text(params.outputPath.isEmpty
                     ? "~/Downloads/PurpleReel/  (default)"
                     : params.outputPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose…") { pickOutput() }
                    .controlSize(.small)
                if !params.outputPath.isEmpty {
                    Button("Reset") { params.outputPath = "" }
                        .controlSize(.small)
                }
            }
        }
    }
    private func pickOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = []
        panel.nameFieldStringValue = "report.\(params.format)"
        if panel.runModal() == .OK, let url = panel.url {
            params.outputPath = url.path
        }
    }
}
