import SwiftUI
import AppKit

/// Warm, one-button setup wizard for the transcription pipeline.
///
/// Design intent: when the user lands here at launch, they should see a
/// short friendly message, a single obvious button, and *not* a
/// 5-row technical checklist or a pip log. The technical state is still
/// available behind a `Show technical details` disclosure for power
/// users and bug reports, but it never gates the primary action.
///
/// State machine the body switches over:
///
///   - Idle, all green     → "Transcription is ready" success panel
///   - Idle, has failures  → Setup prompt: "Set up now / Disable / Not now"
///   - Setup in progress   → Caption + progress bar + (optional) tech log
///   - Setup finished OK   → Success panel
///   - Setup finished bad  → Warm failure panel with concrete actions
///
/// The "Idle, all green" state is what you see when you re-open the
/// sheet via Settings → Run preflight after everything is already
/// working — useful as a confidence check.
struct TranscriptionPreflightSheet: View {
    @ObservedObject var service: TranscriptionPreflightService
    @Binding var isPresented: Bool

    /// Settings master toggle. Reachable from the sheet so a user who
    /// just wants to opt out can do so in one click rather than hunt
    /// through Settings.
    @Binding var masterEnabled: Bool

    /// Disclosure state for the technical details (checklist + pip log).
    /// Defaults closed so the warm view is what users see by default.
    @State private var showTechnicalDetails: Bool = false
    /// Brief "Copied" flash after the user clicks Copy on the log.
    @State private var copiedRecently: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch currentMode {
            case .working:    workingPanel
            case .successful: successPanel
            case .failed:     failurePanel
            case .ready:      readyPanel
            case .needsSetup: needsSetupPanel
            }
            if showTechnicalDetails || service.installLog.count > 0 || alwaysShowChecklist {
                technicalDetails
            } else {
                detailsToggleRow
            }
        }
        .padding(22)
        .frame(width: 560)
    }

    // MARK: - State

    private enum Mode {
        case ready        // probe done, all green, idle
        case needsSetup   // probe done, has failures, not started
        case working      // setup actively in progress
        case successful   // setup finished OK
        case failed       // setup finished with a plain-English reason
    }

    private var currentMode: Mode {
        if case .finishedOK = service.setupPhase { return .successful }
        if case .finishedFailed = service.setupPhase { return .failed }
        if service.isInstalling { return .working }
        if service.allOK { return .ready }
        return .needsSetup
    }

    /// Force the technical disclosure to render (without toggling its
    /// state) when the workflow has emitted log output — power users
    /// looking at the log live shouldn't have to click to keep it open.
    private var alwaysShowChecklist: Bool { service.isInstalling }

    // MARK: - Panels

    /// First-time landing when something needs to be installed. Warm
    /// message, three actions, no checklist by default.
    @ViewBuilder
    private var needsSetupPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform.badge.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
                .frame(width: 36, alignment: .center)
            VStack(alignment: .leading, spacing: 6) {
                Text("Transcription isn't set up yet")
                    .font(.title3).bold()
                Text("To transcribe audio and video attachments, the app needs ffmpeg and a small Python environment. Setup takes a couple of minutes and downloads about 200 MB the first time.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        HStack {
            Button("Disable transcription") {
                masterEnabled = false
                isPresented = false
            }
            .help("You can turn this back on any time in Settings → Transcription.")
            Spacer()
            Button("Not now") { isPresented = false }
            Button("Set up now") {
                Task {
                    let ok = await service.runSetup()
                    if ok { await service.probeAll() }
                }
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    /// In-progress: plain-English caption above a smooth progress bar.
    /// The pip log lives in the disclosure if the user wants it.
    @ViewBuilder
    private var workingPanel: some View {
        HStack(alignment: .center, spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text("Setting up transcription").font(.title3).bold()
                Text(service.setupPhase.caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView(value: service.setupPhase.progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: .infinity)
            }
        }
        HStack {
            Spacer()
            Button("Continue in background") { isPresented = false }
                .help("Setup keeps running. The banner on the main window will let you know when it's done.")
        }
    }

    /// Setup finished green. Big checkmark, one-line confirmation, Done.
    @ViewBuilder
    private var successPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text("Transcription is ready").font(.title3).bold()
                Text("Audio and video attachments will be transcribed automatically when the **Transcribe** toggle is on.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        HStack {
            Spacer()
            Button("Done") { isPresented = false }
                .keyboardShortcut(.defaultAction)
        }
    }

    /// Same green state but reached without a setup run — the user
    /// already had everything installed, or re-opened the sheet from
    /// Settings as a confidence check.
    @ViewBuilder
    private var readyPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text("Transcription is ready").font(.title3).bold()
                Text("All checks passed. The Transcribe toggle on the main form is good to go.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        HStack {
            Button("Disable transcription") {
                masterEnabled = false
                isPresented = false
            }
            Spacer()
            Button("Re-run checks") {
                Task { await service.probeAll() }
            }
            .disabled(service.isProbing || service.isInstalling)
            Button("Done") { isPresented = false }
                .keyboardShortcut(.defaultAction)
        }
    }

    /// Setup couldn't complete. Show the warm reason + concrete actions
    /// rather than a stack trace. Common cases: brew missing, network
    /// down, wheels unavailable, venv corrupt past easy repair.
    @ViewBuilder
    private var failurePanel: some View {
        let reason: String = {
            if case .finishedFailed(let r) = service.setupPhase { return r }
            return "Setup didn't complete."
        }()
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text("Setup didn't complete").font(.title3).bold()
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if reason.contains("Homebrew") {
                    Button {
                        if let url = URL(string: "https://brew.sh") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Open brew.sh", systemImage: "arrow.up.right.square")
                    }
                    .controlSize(.small)
                }
            }
        }
        HStack {
            Button("Disable transcription") {
                masterEnabled = false
                isPresented = false
            }
            Spacer()
            Button("Rebuild from scratch") {
                Task {
                    let ok = await service.rebuildVenv()
                    if ok { await service.probeAll() }
                }
            }
            .help("Deletes the existing Python environment and reinstalls from scratch. Slower but heals more breakage.")
            Button("Try again") {
                Task {
                    let ok = await service.runSetup()
                    if ok { await service.probeAll() }
                }
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Technical details (disclosure)

    /// Small row that opens the disclosure on click. Used when there's
    /// nothing technical to show yet (no setup run).
    @ViewBuilder
    private var detailsToggleRow: some View {
        Divider()
        Button {
            showTechnicalDetails.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: showTechnicalDetails ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                Text("Show technical details")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    /// The 5-row checklist + pip log. Shown only when the user asks for
    /// it (or while setup is mid-run so the log can stream live).
    @ViewBuilder
    private var technicalDetails: some View {
        Divider()
        DisclosureGroup(isExpanded: Binding(
            get: { showTechnicalDetails || alwaysShowChecklist },
            set: { showTechnicalDetails = $0 }
        )) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(service.steps) { step in
                    StepRow(step: step) {
                        Task { await service.probe(step.id) }
                    }
                }
                if !service.installLog.isEmpty {
                    installLogView
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Technical details")
                .font(.caption).bold()
                .foregroundStyle(.secondary)
        }
    }

    /// The collapsible pip / brew output. Behind the disclosure by
    /// default; copy-to-clipboard button for bug reports.
    @ViewBuilder
    private var installLogView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Setup log").font(.caption2).bold()
                Spacer()
                Button(action: copyInstallLog) {
                    HStack(spacing: 4) {
                        Image(systemName: copiedRecently ? "checkmark" : "doc.on.doc")
                        Text(copiedRecently ? "Copied" : "Copy")
                    }
                }
                .controlSize(.mini)
                .buttonStyle(.bordered)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(service.installLog.joined(separator: "\n"))
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(8)
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .frame(height: 120)
                .background(Color.black.opacity(0.05))
                .onChange(of: service.installLog.count) { _, _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private func copyInstallLog() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(service.installLog.joined(separator: "\n"), forType: .string)
        copiedRecently = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedRecently = false
        }
    }
}

/// One row in the technical-details checklist. Status icon + title +
/// detail/fix + Retry. Lives behind the disclosure so the warm view
/// stays uncluttered.
private struct StepRow: View {
    let step: PreflightStep
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(step.title).font(.caption).bold()
                    Spacer(minLength: 6)
                    Button("Retry", action: retry)
                        .controlSize(.mini)
                        .buttonStyle(.borderless)
                }
                if let detail = primaryDetail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let fix = suggestedFix {
                    Text(fix)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch step.status {
        case .pending:   Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        case .checking:  ProgressView().controlSize(.mini)
        case .ok:        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    private var primaryDetail: String? {
        switch step.status {
        case .ok(let detail): return detail
        case .failed(let reason, _): return reason
        case .pending, .checking: return nil
        }
    }

    private var suggestedFix: String? {
        if case .failed(_, let fix) = step.status { return fix }
        return nil
    }
}
