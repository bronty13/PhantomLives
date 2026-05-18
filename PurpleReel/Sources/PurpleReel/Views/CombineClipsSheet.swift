import SwiftUI
import AppKit
import AVFoundation

/// "Combine Clips" sheet (Kyno-parity row 8). Lists the user's
/// current multi-selection in playback order, lets them reorder
/// with up/down buttons, picks an output preset + destination, and
/// kicks `CombineClipsJob.run()` to render the head-to-tail
/// composition into a single file.
///
/// MVP scope: whole-clip concatenation. Per-clip in/out trim is
/// a follow-up — the first cut targets the dominant doc-shooter
/// "glue 8-minute pieces" use case Kyno's release notes describe.
struct CombineClipsSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Sources to combine — initialised from the user's
    /// multi-selection. State so the sheet can reorder without
    /// mutating AppState.
    @State private var sources: [Asset]
    @State private var presetID: String = "prores-422"
    @State private var dest: URL?
    @State private var filename: String = "combined.mov"
    @State private var job: CombineClipsJob?

    init(initialSources: [Asset]) {
        _sources = State(initialValue: initialSources)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            sourcesList
            Divider()
            outputControls
            if let job {
                Divider()
                progressRow(job: job)
            }
            Spacer()
            footer
        }
        .padding(20)
        .frame(width: 640, height: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Combine Clips")
                .font(.title3.weight(.semibold))
            Text("Renders the listed clips head-to-tail into a single file. Drag-free reordering — use the arrows. Resolution comes from the first clip; mixed sizes will letterbox.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var sourcesList: some View {
        if sources.count < 2 {
            Text("Select two or more clips before opening this sheet.")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Order (top → bottom = first → last)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(sources.enumerated()), id: \.element.path) { idx, asset in
                            HStack(spacing: 8) {
                                Text("\(idx + 1).")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, alignment: .trailing)
                                Text(asset.filename)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(durationLabel(asset))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Button {
                                    move(idx, by: -1)
                                } label: { Image(systemName: "arrow.up") }
                                .buttonStyle(.borderless)
                                .disabled(idx == 0)
                                Button {
                                    move(idx, by: 1)
                                } label: { Image(systemName: "arrow.down") }
                                .buttonStyle(.borderless)
                                .disabled(idx == sources.count - 1)
                                Button {
                                    sources.remove(at: idx)
                                } label: { Image(systemName: "xmark.circle") }
                                .buttonStyle(.borderless)
                                .help("Remove from combine list")
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .background(
                                idx % 2 == 0
                                ? Color.secondary.opacity(0.05)
                                : Color.clear
                            )
                        }
                    }
                }
                .frame(maxHeight: 220)
                Text("Total: \(totalDurationLabel) · \(sources.count) clip(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var outputControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Preset:")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
                Picker("", selection: $presetID) {
                    ForEach(combinePresets, id: \.id) { p in
                        Text(p.name).tag(p.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
                .onChange(of: presetID) { _, _ in retitleForPreset() }
            }
            HStack(spacing: 8) {
                Text("Save to:")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
                Text(dest?.path ?? "—")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(dest == nil ? .secondary : .primary)
                Spacer()
                Button("Choose…") { pickDest() }
            }
            HStack(spacing: 8) {
                Text("Filename:")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $filename)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func progressRow(job: CombineClipsJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch job.state {
            case .queued:
                ProgressView().controlSize(.small)
            case .running:
                ProgressView(value: job.progress)
                Text("Rendering… \(Int(job.progress * 100))%")
                    .font(.caption).foregroundStyle(.secondary)
            case .finished(let url):
                Text("Done: \(url.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failed(let msg):
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
            case .cancelled:
                Text("Cancelled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let job, job.state == .running {
                Button("Cancel Render") { job.cancel() }
            } else {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            Button("Combine") { runCombine() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canRun)
        }
    }

    // MARK: - Helpers

    private var canRun: Bool {
        sources.count >= 2
            && dest != nil
            && !filename.isEmpty
            && job?.state != .running
    }

    private var combinePresets: [TranscodePreset] {
        // Combine only makes sense for the native AVFoundation
        // presets — ffmpeg recipes don't accept a composition. Drop
        // pass-through too (composition is, by definition, not the
        // source).
        TranscodePreset.all.filter {
            !$0.isFFmpeg
            && $0.avPresetName != AVAssetExportPresetPassthrough
        }
    }

    private var selectedPreset: TranscodePreset? {
        combinePresets.first { $0.id == presetID }
            ?? combinePresets.first
    }

    private func move(_ index: Int, by delta: Int) {
        let target = index + delta
        guard target >= 0, target < sources.count else { return }
        sources.swapAt(index, target)
    }

    private func pickDest() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        // Default to ~/Downloads/PurpleReel/combined/ per the
        // PhantomLives output-location convention. Created if
        // absent so the picker doesn't dead-end the user.
        let downloads = FileManager.default.urls(
            for: .downloadsDirectory, in: .userDomainMask
        ).first
        let suggested = downloads?
            .appendingPathComponent("PurpleReel", isDirectory: true)
            .appendingPathComponent("combined", isDirectory: true)
        if let s = suggested {
            try? FileManager.default.createDirectory(
                at: s, withIntermediateDirectories: true
            )
            panel.directoryURL = s
        }
        if panel.runModal() == .OK, let url = panel.url {
            dest = url
        }
    }

    private func retitleForPreset() {
        let ext = (selectedPreset?.avPresetName == AVAssetExportPresetAppleProRes422LPCM
                   || selectedPreset?.avPresetName == AVAssetExportPresetAppleProRes4444LPCM)
                  ? "mov" : "mp4"
        let base = (filename as NSString).deletingPathExtension
        filename = base.isEmpty ? "combined.\(ext)" : "\(base).\(ext)"
    }

    private func runCombine() {
        guard let preset = selectedPreset, let dest else { return }
        let outURL = dest.appendingPathComponent(filename)
        let urls = sources.map { URL(fileURLWithPath: $0.path) }
        let j = CombineClipsJob(sources: urls,
                                 outputURL: outURL,
                                 preset: preset)
        self.job = j
        Task {
            await j.run()
            // Reveal the file on success; leave the sheet open so
            // the user can read the result line.
            if case .finished(let url) = j.state {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                await appState.rescan()
            }
        }
    }

    private func durationLabel(_ asset: Asset) -> String {
        let s = asset.durationSeconds ?? 0
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
    private var totalDurationLabel: String {
        let total = Int(sources.reduce(0.0) { $0 + ($1.durationSeconds ?? 0) })
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
