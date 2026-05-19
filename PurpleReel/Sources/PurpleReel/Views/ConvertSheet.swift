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
    /// Output-filename template (C4). Defaults to the legacy
    /// `<base><preset.suffix>.<ext>` shape so existing users see the
    /// same names; the dialog Picker lets them switch to Kyno's
    /// "Original name + Transcoding Preset" or "Original name only".
    var filenamePattern: FilenamePattern = .originalPlusSuffix
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
    /// "More Options" disclosure (Kyno-parity). Collapses fades + TC
    /// burn-in by default so the main dialog stays close to Kyno's
    /// compact layout; power users expand to see the same controls
    /// PurpleReel has always shipped.
    @State private var showMoreOptions: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    destinationSection
                    Divider()
                    presetSection
                    Divider()
                    summaryLine
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 720, height: 580)
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
                Text("File name pattern:").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Picker("", selection: $state.filenamePattern) {
                        ForEach(FilenamePattern.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320, alignment: .leading)
                    if let example = exampleFilename {
                        HStack(spacing: 6) {
                            Text("Example:")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text(example)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                    collisionWarningRow
                }
                .gridCellColumns(2)
            }
        }
        DisclosureGroup("More Options", isExpanded: $showMoreOptions) {
            moreOptionsContent
                .padding(.top, 8)
        }
        .font(.callout)
    }

    /// Fades + TC burn-in — relocated under the "More Options"
    /// disclosure so the main dialog footprint matches Kyno's. Same
    /// controls as before, same scope (AVFoundation-only).
    @ViewBuilder
    private var moreOptionsContent: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
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

    /// Live filename preview for the first asset in the batch. nil
    /// when the batch is empty (which shouldn't happen — the menu
    /// gates against zero — but keeps the UI safe).
    private var exampleFilename: String? {
        guard let first = state.assets.first else { return nil }
        let url = URL(fileURLWithPath: first.path)
        let base = url.deletingPathExtension().lastPathComponent
        let stem = TranscodeService.stem(
            from: base, preset: state.preset,
            pattern: state.filenamePattern
        )
        return "\(stem).\(state.preset.fileExtension)"
    }

    /// Collision warning row. Walks the batch building each output
    /// URL and counts how many already exist on disk. Mirrors Kyno's
    /// "25 warnings: Would overwrite existing file" badge.
    @ViewBuilder
    private var collisionWarningRow: some View {
        let count = collisionCount
        if count > 0 {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("\(count) \(count == 1 ? "warning" : "warnings"): Would overwrite existing file")
                    .foregroundStyle(.orange)
                if state.skipExisting {
                    Text("(will be skipped)")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }

    private var collisionCount: Int {
        let baseDir = URL(fileURLWithPath:
            (state.destinationDir as NSString).expandingTildeInPath)
        var collisions = 0
        for asset in state.assets {
            let url = URL(fileURLWithPath: asset.path)
            let base = url.deletingPathExtension().lastPathComponent
            let stem = TranscodeService.stem(
                from: base, preset: state.preset,
                pattern: state.filenamePattern
            )
            let candidate = baseDir.appendingPathComponent(
                "\(stem).\(state.preset.fileExtension)"
            )
            if FileManager.default.fileExists(atPath: candidate.path) {
                collisions += 1
            }
        }
        return collisions
    }

    /// Kyno-shaped Conversion Preset section: header with name +
    /// (edited) indicator, then per-channel File format / Video /
    /// Audio / Trimming rows showing the preset's effective config.
    /// The per-channel rows render as read-only descriptions in C4 —
    /// Copy/Re-encode editing + Settings… tabbed editor land in C5
    /// (gated behind the composable runtime that C3 just landed).
    @ViewBuilder
    private var presetSection: some View {
        HStack(spacing: 8) {
            Text("Conversion Preset: \(state.preset.name)")
                .font(.title3.weight(.semibold))
            if isEdited {
                Text("(edited)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "gearshape")
                .foregroundStyle(.secondary)
                .help("Preset management — Save As / Reset coming in C5")
            Spacer()
        }
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            channelRow(label: "File format:",
                        value: state.preset.fileExtension.uppercased(),
                        descriptor: fileFormatDescriptor)
            channelRow(label: "Video:",
                        value: videoChannelLabel,
                        descriptor: videoDescriptor)
            channelRow(label: "Audio:",
                        value: audioChannelLabel,
                        descriptor: audioDescriptor)
            channelRow(label: "Trimming:",
                        value: "None",
                        descriptor: "No in/out trim applied")
        }
        .font(.callout)
    }

    /// One row of the per-channel grid: label + current value + a
    /// short descriptor + (stubbed) Settings… button. Disabled
    /// settings button + tooltip flags this as a C5 deliverable.
    @ViewBuilder
    private func channelRow(label: String,
                             value: String,
                             descriptor: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(value)
                    .frame(minWidth: 90, alignment: .leading)
                Text(descriptor)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Button("Settings…") {}
                .disabled(true)
                .help("Per-channel editing — Encoding / Filters / LUTs / Overlays tabs land in C5")
        }
    }

    /// Whether any user-edited fields diverge from the preset's
    /// defaults. Today the only divergence the dialog can express is
    /// the filename pattern (everything else is read-only); the
    /// (edited) indicator stays accurate for the C5 rollout of the
    /// full options editor.
    private var isEdited: Bool {
        state.filenamePattern != .originalPlusSuffix
    }

    private var fileFormatDescriptor: String {
        let bits: [String] = state.preset.isFFmpeg
            ? ["ffmpeg", state.preset.category.displayName]
            : ["Streamable", "Source Timecode"]
        return bits.joined(separator: ", ")
    }

    /// "Copy" when the preset rewraps without re-encoding; "Re-Encode"
    /// otherwise. Derived from the AVAssetExportSession preset name
    /// because that's the cleanest signal we have today.
    private var videoChannelLabel: String {
        state.preset.avPresetName == "AVAssetExportPresetPassthrough"
            ? "Copy" : "Re-Encode"
    }

    private var audioChannelLabel: String {
        // Mirror the video channel — pass-through preset copies both
        // streams; every re-encode preset re-encodes audio too.
        videoChannelLabel
    }

    private var videoDescriptor: String {
        if state.preset.avPresetName == "AVAssetExportPresetPassthrough" {
            return "Do not re-encode"
        }
        // Surface the effective codec + size based on the preset's
        // AVAssetExportSession constant; ffmpeg presets use the
        // preset's display name as the descriptor.
        if state.preset.isFFmpeg {
            return state.preset.name
        }
        return "\(state.preset.name), Size Like Source"
    }

    private var audioDescriptor: String {
        if state.preset.avPresetName == "AVAssetExportPresetPassthrough" {
            return "Do not re-encode"
        }
        return "AAC, 48 kHz, 192 kbit/s"
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
