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
    /// C5 — composable editing. Initialized from the preset's
    /// defaults on first render; the Settings… sheets bind through
    /// `$editableOptions` so edits flow back here. When this diverges
    /// from `state.preset.defaultOptions()` we route the job through
    /// the composable runtime instead of the legacy preset path.
    @State private var editableOptions: TranscodeOptions = TranscodeOptions()
    @State private var optionsBaseline: TranscodeOptions = TranscodeOptions()
    @State private var didInitOptions: Bool = false

    @State private var showContainerSettings: Bool = false
    @State private var showVideoSettings: Bool = false
    @State private var showAudioSettings: Bool = false

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
        .onAppear {
            guard !didInitOptions else { return }
            var base = state.preset.defaultOptions()
            // C36 — auto-default LUT pickers from the pinned per-
            // clip Camera / Creative LUT paths (C30). Only fires
            // when exactly one asset is being transcoded — for
            // batch jobs the right policy is ambiguous (which
            // clip's LUT wins?) so leave it manual.
            if state.assets.count == 1,
               let rowId = state.assets.first?.rowId,
               let meta = appState.clipMetadataIndex[rowId] {
                if let cam = meta.cameraLUTPath, !cam.isEmpty {
                    base.cameraLUT = .file(path: cam)
                }
                if let creative = meta.creativeLUTPath, !creative.isEmpty {
                    base.creativeLUT = .file(path: creative)
                }
            }
            editableOptions = base
            optionsBaseline = base
            didInitOptions = true
        }
        .sheet(isPresented: $showContainerSettings) {
            ContainerSettingsSheet(
                settings: $editableOptions.containerSettings,
                timecodeSource: Binding(
                    get: { editableOptions.containerSettings.timecodeSource },
                    set: { editableOptions.containerSettings.timecodeSource = $0 }
                )
            )
        }
        .sheet(isPresented: $showAudioSettings) {
            AudioSettingsSheet(channel: $editableOptions.audio)
        }
        .sheet(isPresented: $showVideoSettings) {
            VideoSettingsSheet(options: $editableOptions)
        }
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
                    // C22 — Recent destinations dropdown. Hidden
                    // when the list is empty (first-run UX is the
                    // same as before; menu shows up once the user
                    // has picked at least one folder).
                    recentsMenu
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
                Button("Reset") {
                    editableOptions = optionsBaseline
                    state.filenamePattern = .originalPlusSuffix
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            Spacer()
        }
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            // File format row — Picker is functional; Settings opens
            // container settings.
            GridRow {
                Text("File format:").foregroundStyle(.secondary)
                Picker("", selection: containerBinding) {
                    Text("MOV").tag(ContainerFormat.mov)
                    Text("MP4").tag(ContainerFormat.mp4)
                    Text("MKV").tag(ContainerFormat.mkv)
                    Text("MXF").tag(ContainerFormat.mxf)
                    Text("Audio Only").tag(ContainerFormat.audioOnly)
                }
                .labelsHidden()
                .frame(width: 140, alignment: .leading)
                HStack {
                    Text(fileFormatDescriptor)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Settings…") { showContainerSettings = true }
                }
            }
            // Video row — Picker toggles Copy ↔ Re-Encode.
            GridRow {
                Text("Video:").foregroundStyle(.secondary)
                Picker("", selection: videoChannelModeBinding) {
                    Text("Copy").tag(ChannelMode.copy)
                    Text("Re-Encode").tag(ChannelMode.reencode)
                    Text("Off").tag(ChannelMode.disabled)
                }
                .labelsHidden()
                .frame(width: 140, alignment: .leading)
                HStack {
                    Text(videoDescriptor)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Button("Settings…") { showVideoSettings = true }
                }
            }
            // Audio row.
            GridRow {
                Text("Audio:").foregroundStyle(.secondary)
                Picker("", selection: audioChannelModeBinding) {
                    Text("Copy").tag(ChannelMode.copy)
                    Text("Re-Encode").tag(ChannelMode.reencode)
                    Text("Off").tag(ChannelMode.disabled)
                }
                .labelsHidden()
                .frame(width: 140, alignment: .leading)
                HStack {
                    Text(audioDescriptor)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Settings…") { showAudioSettings = true }
                }
            }
            // Trimming row.
            GridRow {
                Text("Trimming:").foregroundStyle(.secondary)
                Picker("", selection: $editableOptions.trimming) {
                    Text("None").tag(Trimming.none)
                    Text("In - Out").tag(Trimming.inToOut)
                }
                .labelsHidden()
                .frame(width: 140, alignment: .leading)
                Text(editableOptions.trimming == .inToOut
                      ? "Use clip In/Out marks (if set)"
                      : "No in/out trim applied")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.callout)
    }

    // MARK: - Channel mode (Copy / Re-Encode / Off) bindings

    enum ChannelMode: Hashable { case copy, reencode, disabled }

    private var videoChannelModeBinding: Binding<ChannelMode> {
        Binding(
            get: {
                switch editableOptions.video {
                case .copy:        return .copy
                case .disabled:    return .disabled
                case .reencode(_): return .reencode
                }
            },
            set: { newMode in
                switch newMode {
                case .copy:     editableOptions.video = .copy
                case .disabled: editableOptions.video = .disabled
                case .reencode:
                    // Switching back to Re-Encode restores the baseline's
                    // VideoEncoding if it had one, else defaults to H.264.
                    if case .reencode(let prior) = optionsBaseline.video {
                        editableOptions.video = .reencode(prior)
                    } else {
                        editableOptions.video = .reencode(.defaultH264)
                    }
                }
            }
        )
    }

    private var audioChannelModeBinding: Binding<ChannelMode> {
        Binding(
            get: {
                switch editableOptions.audio {
                case .copy:        return .copy
                case .disabled:    return .disabled
                case .reencode(_): return .reencode
                }
            },
            set: { newMode in
                switch newMode {
                case .copy:     editableOptions.audio = .copy
                case .disabled: editableOptions.audio = .disabled
                case .reencode:
                    if case .reencode(let prior) = optionsBaseline.audio {
                        editableOptions.audio = .reencode(prior)
                    } else {
                        editableOptions.audio = .reencode(.defaultAAC)
                    }
                }
            }
        )
    }

    private var containerBinding: Binding<ContainerFormat> {
        $editableOptions.container
    }

    // MARK: - Edited detection + descriptors

    /// True when the user has touched the composable options or the
    /// filename pattern. Drives the (edited) indicator + the runtime
    /// routing decision in confirmConvert.
    var isEdited: Bool {
        editableOptions != optionsBaseline
            || state.filenamePattern != .originalPlusSuffix
    }

    private var fileFormatDescriptor: String {
        switch editableOptions.container {
        case .mov:       return "Streamable, Source Timecode"
        case .mp4:       return "Streamable, Source Timecode"
        case .mkv:       return "Matroska container"
        case .mxf:       return "Broadcast container"
        case .audioOnly: return "Audio-only output"
        }
    }

    private var videoDescriptor: String {
        switch editableOptions.video {
        case .copy:     return "Do not re-encode"
        case .disabled: return "Video disabled"
        case .reencode(let e):
            var bits: [String] = [e.codec.displayName]
            switch e.size {
            case .likeSource:                  bits.append("Size Like Source")
            case .fixed(let w, let h):         bits.append("\(w)×\(h)")
            case .scale(let f):                bits.append(String(format: "%g×", f))
            }
            if case .bitrate(let kbps) = e.quality {
                bits.append("\(kbps) kbit/s")
            }
            return bits.joined(separator: ", ")
        }
    }

    private var audioDescriptor: String {
        switch editableOptions.audio {
        case .copy:     return "Do not re-encode"
        case .disabled: return "Audio disabled"
        case .reencode(let a):
            return "\(a.codec.displayName), \(a.sampleRate / 1000) kHz, \(a.bitrateKbps) kbit/s"
        }
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
            Button("Start") {
                // Pass the live editableOptions through if the user
                // has diverged from the preset's defaults — confirmConvert
                // routes the job through the composable runtime in that
                // case. If unchanged, the legacy preset path runs.
                let optionsArg = editableOptions == optionsBaseline
                    ? nil : editableOptions
                appState.confirmConvert(state, editedOptions: optionsArg)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    /// C22 — small Menu next to the Select… button listing the
    /// last 6 destinations the user picked in any Convert session.
    /// Hidden when the list is empty so the dialog looks identical
    /// to pre-C22 on first run.
    @ViewBuilder
    private var recentsMenu: some View {
        let recents = RecentDestinations.list(.convert)
        if !recents.isEmpty {
            Menu {
                ForEach(recents, id: \.path) { url in
                    Button {
                        state.destinationDir = url.path
                        RecentDestinations.push(url, scope: .convert)
                    } label: {
                        Text(url.path)
                    }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .help("Recent destinations")
        }
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
            // C22 — record on the convert-scope recents list so the
            // user's next session can re-pick this folder without
            // re-traversing the picker.
            RecentDestinations.push(url, scope: .convert)
        }
    }
}
