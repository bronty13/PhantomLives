import SwiftUI
import AppKit

/// User-editable state shared between AppState (owns the truth) and
/// `ConvertSheet` (the UI). Lives outside the view so other call sites
/// — toolbar menus, keyboard shortcuts — can compose it identically.
struct ConvertSheetState: Identifiable {
    let id = UUID()
    var assets: [Asset]
    var preset: TranscodePreset
    var destinationDir: String
    var keepFolderStructure: Bool
    var skipExisting: Bool
    /// Audio + video fade-in length applied at the start of every
    /// output clip. Zero = off. Honored only on AVFoundation presets;
    /// ffmpeg recipes ignore this for now (filter-chain merge is a
    /// follow-up).
    var fadeInSeconds: Double = 0
    /// Same shape as `fadeInSeconds` but applied at the end of each
    /// output clip — fade to black + audio cross-fade to silence.
    var fadeOutSeconds: Double = 0
    /// Burn the running source timecode into every output frame.
    /// Required for any dailies / client-review workflow. Honored
    /// only on AVFoundation presets (same scope as fades).
    var tcBurnIn: Bool = false

    /// Longest path that is a prefix of every input path. Used for
    /// the "keep folder structure" relative-path computation.
    /// Returns nil for empty / fully-disjoint inputs.
    static func commonAncestor(of paths: [String]) -> String? {
        guard let first = paths.first else { return nil }
        var prefix = first
        for p in paths.dropFirst() {
            while !p.hasPrefix(prefix) {
                if let slash = prefix.lastIndex(of: "/") {
                    prefix = String(prefix[..<slash])
                    if prefix.isEmpty { return "/" }
                } else {
                    return nil
                }
            }
        }
        return prefix
    }
}

/// "Convert & Transcode Media" dialog — Kyno's pre-queue editor.
/// Shown when the user picks a preset from the Convert submenu; lets
/// them set destination, keep-folder-structure, skip-if-exists, and
/// review the file count before pressing Start.
struct ConvertSheet: View {
    @EnvironmentObject var appState: AppState
    @State var state: ConvertSheetState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    destinationSection
                    Divider()
                    presetSummarySection
                    Divider()
                    summaryLine
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 640, height: 460)
    }

    private var header: some View {
        HStack {
            Text("Convert & Transcode Media")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var destinationSection: some View {
        Text("Destination").font(.title3.weight(.semibold))
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Directory:").foregroundStyle(.secondary)
                HStack {
                    TextField("", text: $state.destinationDir)
                        .textFieldStyle(.roundedBorder)
                    Button("Select…") { pickDestination() }
                }
                .gridCellColumns(2)
            }
            GridRow {
                Text("Options:").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Keep folder structure from source",
                            isOn: $state.keepFolderStructure)
                    Toggle("Skip items that already exist on target",
                            isOn: $state.skipExisting)
                }
                .gridCellColumns(2)
            }
            GridRow {
                Text("Fades:").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Stepper(value: $state.fadeInSeconds,
                             in: 0...10, step: 0.5) {
                        Text(state.fadeInSeconds > 0
                              ? "Fade in: \(String(format: "%.1f", state.fadeInSeconds)) sec"
                              : "Fade in: off")
                    }
                    .disabled(state.preset.isFFmpeg)
                    Stepper(value: $state.fadeOutSeconds,
                             in: 0...10, step: 0.5) {
                        Text(state.fadeOutSeconds > 0
                              ? "Fade out: \(String(format: "%.1f", state.fadeOutSeconds)) sec"
                              : "Fade out: off")
                    }
                    .disabled(state.preset.isFFmpeg)
                    Toggle("Burn timecode into video", isOn: $state.tcBurnIn)
                        .disabled(state.preset.isFFmpeg)
                    if state.preset.isFFmpeg {
                        Text("Fades + TC burn-in currently apply to AVFoundation presets only. ffmpeg recipes (DNxHR, Cineform, MXF, Smart Proxy) render without them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .gridCellColumns(2)
            }
        }
    }

    @ViewBuilder
    private var presetSummarySection: some View {
        Text("Conversion Preset: \(state.preset.name)")
            .font(.title3.weight(.semibold))
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("File format:").foregroundStyle(.secondary)
                Text(state.preset.fileExtension.uppercased())
            }
            GridRow {
                Text("Category:").foregroundStyle(.secondary)
                Text(state.preset.category.displayName)
            }
            GridRow {
                Text("Engine:").foregroundStyle(.secondary)
                Text(state.preset.isFFmpeg ? "ffmpeg" : "AVFoundation")
            }
            GridRow {
                Text("Suffix:").foregroundStyle(.secondary)
                Text(state.preset.suffix)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private var summaryLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(summary)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private var summary: String {
        let n = state.assets.count
        let f = n == 1 ? "One file" : "\(n) files"
        return "\(f) will be created in \(state.destinationDir)"
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { appState.convertSheet = nil }
                .keyboardShortcut(.cancelAction)
            Button("Start") { appState.confirmConvert(state) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func pickDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath:
            (state.destinationDir as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url {
            state.destinationDir = url.path
        }
    }
}
