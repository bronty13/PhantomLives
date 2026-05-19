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

    /// Sources to combine, in play order. C16 — switched from
    /// `[Asset]` to per-row state so the user can set trim in/out
    /// per clip and drag rows around. Each row carries the source
    /// asset plus its current trim text (separate from the parsed
    /// seconds — kept as strings so the user can type freely before
    /// validation runs at Combine time).
    struct Row: Identifiable {
        let id = UUID()
        let asset: Asset
        var trimInText: String = ""
        var trimOutText: String = ""
        /// C17 — cached marker rows for this source, fetched at
        /// sheet open. The badge in `rowView` counts these; the
        /// runCombine pass forwards them into `CombineSource` so the
        /// service can offset them onto the combined timeline.
        var sourceMarkers: [Marker] = []
        /// C24 — per-pair cross-fade override (seconds). Empty
        /// string = inherit the sheet's global crossfade. Service
        /// clamps to half of `min(thisDur, nextDur)`. Ignored on
        /// the last row.
        var crossfadeAfterText: String = ""
        /// C36 — per-pair easing override. nil = inherit the
        /// sheet's global crossfadeEasing. Ignored on the last
        /// row + when this pair's cross-fade duration is 0.
        var crossfadeEasingAfter: CrossfadeEasing? = nil
    }

    @State private var rows: [Row]
    @State private var presetID: String = "prores-422"
    @State private var dest: URL?
    @State private var filename: String = "combined.mov"
    @State private var job: CombineClipsJob?
    /// C17 — opt-out switch. Defaults to on because the dominant
    /// use case ("glue interview takes") wants markers carried; the
    /// off branch exists for users who want a totally fresh output
    /// (e.g. delivering to a client who shouldn't see the editor's
    /// review notes).
    @State private var preserveMarkers: Bool = true
    /// C19 — canvas-size policy picker. Stored as an Int because
    /// SwiftUI's Picker doesn't play with associated-value enums;
    /// we project to/from `CombineDimensionMode` at runCombine time.
    /// 0 = .firstClip (default, pre-C19 behavior), 1 = .largestSource,
    /// 2 = .explicit(W, H).
    @State private var dimensionModeKind: Int = 0
    @State private var explicitWidthText: String = "1920"
    @State private var explicitHeightText: String = "1080"
    /// C20 — cross-fade duration in seconds; 0 = hard cut (default,
    /// pre-C20 behavior). Stored as String so the user can type
    /// freely; parsed at runCombine time. Service clamps to half
    /// of the shortest trimmed segment.
    @State private var crossfadeText: String = "0"
    /// C23 — fade-from-black on the first clip's leading edge, and
    /// fade-to-black on the last clip's trailing edge. Both 0 by
    /// default. Service clamps each against the corresponding edge
    /// clip's trimmed duration.
    @State private var fadeFromBlackText: String = "0"
    @State private var fadeToBlackText: String = "0"
    /// C27 — easing curve applied to all cross-fade + edge ramps.
    /// `.linear` matches pre-C27 behavior; others approximate via
    /// 8 piecewise-linear segments per fade.
    @State private var crossfadeEasing: CrossfadeEasing = .linear

    init(initialSources: [Asset]) {
        _rows = State(initialValue: initialSources.map {
            Row(asset: $0)
        })
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
        .frame(width: 640, height: 720)
        .onAppear { loadSourceMarkers() }
    }

    /// C17 — fetch each source asset's catalogued markers up-front
    /// so the badge can render immediately and the runCombine pass
    /// has them ready without an extra DB round-trip. Errors fall
    /// back to `[]` (no badge, no preservation) rather than blocking
    /// the sheet.
    private func loadSourceMarkers() {
        for i in rows.indices {
            guard let aid = rows[i].asset.rowId else { continue }
            rows[i].sourceMarkers = (try? appState.db.markers(assetId: aid)) ?? []
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Combine Clips")
                .font(.title3.weight(.semibold))
            Text("Renders the listed clips head-to-tail into a single file. Drag rows to reorder. Set in/out trim per clip (HH:MM:SS or seconds; blank = full clip). Resolution comes from the first clip; mixed sizes will letterbox. Markers on each clip are carried onto the combined timeline.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var sourcesList: some View {
        if rows.count < 2 {
            Text("Select two or more clips before opening this sheet.")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Order (top → bottom = first → last). Drag rows to reorder.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                // C16 — native List with .onMove for drag-reorder.
                // Each row now carries inline in/out trim fields so
                // the user can clip the leading/trailing slop off
                // each source before the head-to-tail render.
                List {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, _ in
                        rowView(at: idx)
                    }
                    .onMove { src, dst in rows.move(fromOffsets: src, toOffset: dst) }
                    .onDelete { offsets in rows.remove(atOffsets: offsets) }
                }
                .listStyle(.bordered)
                .frame(minHeight: 200, maxHeight: 260)
                Text("Total: \(totalDurationLabel) · \(rows.count) clip(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func rowView(at idx: Int) -> some View {
        let row = rows[idx]
        HStack(spacing: 8) {
            Text("\(idx + 1).")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.asset.filename)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text("In")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("00:00:00", text: Binding(
                        get: { rows[idx].trimInText },
                        set: { rows[idx].trimInText = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .frame(width: 90)
                    Text("Out")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField(durationLabel(row.asset),
                              text: Binding(
                                get: { rows[idx].trimOutText },
                                set: { rows[idx].trimOutText = $0 }
                              ))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .frame(width: 90)
                    Text("full \(durationLabel(row.asset))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    // C24 — per-pair cross-fade override. Hidden on
                    // the last row (no neighbor to fade into) and
                    // when there's only one source (nothing to
                    // fade). Empty text = inherit global default.
                    if idx < rows.count - 1, rows.count >= 2 {
                        Text("·").foregroundStyle(.secondary).font(.caption2)
                        Text("CF→")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("",
                                   text: Binding(
                                    get: { rows[idx].crossfadeAfterText },
                                    set: { rows[idx].crossfadeAfterText = $0 }
                                   ))
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                        .frame(width: 50)
                        .help("Cross-fade duration in seconds after this clip. Empty = use the default below.")
                        // C36 — per-pair easing override Menu. Default
                        // "Inherit" leaves the global crossfadeEasing
                        // to drive this pair's curve.
                        Menu {
                            Button("Inherit (default)") {
                                rows[idx].crossfadeEasingAfter = nil
                            }
                            Divider()
                            ForEach(
                                [CrossfadeEasing.linear, .easeIn, .easeOut, .easeInOut],
                                id: \.self
                            ) { e in
                                Button(easingLabel(e)) {
                                    rows[idx].crossfadeEasingAfter = e
                                }
                            }
                        } label: {
                            Image(systemName: rows[idx].crossfadeEasingAfter == nil
                                  ? "function" : "function.fill")
                                .foregroundStyle(rows[idx].crossfadeEasingAfter == nil
                                                  ? AnyShapeStyle(HierarchicalShapeStyle.secondary)
                                                  : AnyShapeStyle(TintShapeStyle.tint))
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 24)
                        .help(rows[idx].crossfadeEasingAfter
                              .map { "Curve: \(easingLabel($0))" }
                              ?? "Curve: inherit global default")
                    }
                    if preserveMarkers, !row.sourceMarkers.isEmpty {
                        // C17 — badge counts the markers about to be
                        // carried across. Filter/offset happens in the
                        // service; this count is just the upper bound
                        // (markers fully outside trim drop later).
                        Label("\(row.sourceMarkers.count)", systemImage: "bookmark.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2)
                            .foregroundStyle(.tint)
                            .help("\(row.sourceMarkers.count) marker(s) on this clip will be carried into the combined output (some may drop if outside the trim range).")
                    }
                }
            }
            Spacer()
            Button {
                rows.remove(at: idx)
            } label: { Image(systemName: "xmark.circle") }
            .buttonStyle(.borderless)
            .help("Remove from combine list")
        }
        .padding(.vertical, 4)
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
                // C22 — Recent destinations dropdown. Hidden when
                // empty (first-run UX matches pre-C22).
                recentsMenu
                Button("Choose…") { pickDest() }
            }
            HStack(spacing: 8) {
                Text("Filename:")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $filename)
                    .textFieldStyle(.roundedBorder)
            }
            // C19 — canvas-size policy picker. Hidden for audio-only
            // presets (no video canvas to pick). The W/H fields show
            // up only when `.explicit` is the active choice.
            if selectedPreset?.isAudioOnly == false {
                HStack(spacing: 8) {
                    Text("Canvas size:")
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                    Picker("", selection: $dimensionModeKind) {
                        Text("Match first clip").tag(0)
                        Text("Largest source").tag(1)
                        Text("Custom WxH").tag(2)
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                    if dimensionModeKind == 2 {
                        TextField("W", text: $explicitWidthText)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption.monospaced())
                            .frame(width: 70)
                        Text("×")
                            .foregroundStyle(.secondary)
                        TextField("H", text: $explicitHeightText)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption.monospaced())
                            .frame(width: 70)
                    }
                    Spacer()
                }
            }
            // C20 — cross-fade duration. 0 = hard cut (default,
            // pre-C20 behavior). Audio-only outputs cross-fade the
            // audio; video presets cross-fade both video & audio.
            // Service clamps to half of shortest segment at run time.
            HStack(spacing: 8) {
                Text("Cross-fade:")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
                TextField("0", text: $crossfadeText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .frame(width: 70)
                Text("default seconds — per-clip CF→ overrides above")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            // C23 — edge fade-from/to-black. Independent of
            // cross-fade; either can be used alone (e.g. fade-from-
            // black on a single concatenated piece with hard cuts in
            // between).
            HStack(spacing: 8) {
                Text("Fade in:")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
                TextField("0", text: $fadeFromBlackText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .frame(width: 70)
                Text("sec from black on first clip")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 8) {
                Text("Fade out:")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
                TextField("0", text: $fadeToBlackText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .frame(width: 70)
                Text("sec to black on last clip")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            // C27 — easing curve picker. Hidden when no cross-fade
            // or edge fade is active (nothing to ease).
            HStack(spacing: 8) {
                Text("Easing:")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
                Picker("", selection: $crossfadeEasing) {
                    Text("Linear").tag(CrossfadeEasing.linear)
                    Text("Ease In").tag(CrossfadeEasing.easeIn)
                    Text("Ease Out").tag(CrossfadeEasing.easeOut)
                    Text("Ease In-Out (smoothstep)").tag(CrossfadeEasing.easeInOut)
                }
                .labelsHidden()
                .frame(maxWidth: 220)
                Text("curve for all fades")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            // C17 — preserve-markers toggle. Hidden when no source
            // has any markers (nothing to preserve, no need to
            // surface the option).
            if anySourceHasMarkers {
                Toggle(isOn: $preserveMarkers) {
                    HStack(spacing: 4) {
                        Image(systemName: "bookmark.fill")
                        Text("Preserve markers on combined output")
                    }
                }
                .toggleStyle(.checkbox)
                .help("Carry each source clip's markers onto the combined timeline, offset to the right segment. Markers outside the trim range are dropped.")
            }
        }
    }

    private var anySourceHasMarkers: Bool {
        rows.contains { !$0.sourceMarkers.isEmpty }
    }

    /// C19 — project the picker's Int kind + text fields back into
    /// a `CombineDimensionMode`. Unparseable explicit W/H falls back
    /// to `.firstClip` so a typo doesn't blow up the export — the
    /// user can fix the field and re-Combine.
    private func resolvedDimensionMode() -> CombineDimensionMode {
        switch dimensionModeKind {
        case 1: return .largestSource
        case 2:
            if let w = Int(explicitWidthText), let h = Int(explicitHeightText),
               w > 0, h > 0 {
                return .explicit(width: w, height: h)
            }
            return .firstClip
        default: return .firstClip
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
        rows.count >= 2
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

    // C16 — drag-reorder via List/.onMove replaces the up/down
    // arrows. The legacy `move(_:by:)` helper is no longer needed.

    /// C22 — small Menu next to the Choose… button listing the
    /// last 6 destinations the user picked in any Combine session.
    /// Hidden when the list is empty (first-run UX matches pre-C22).
    @ViewBuilder
    private var recentsMenu: some View {
        let recents = RecentDestinations.list(.combine)
        if !recents.isEmpty {
            Menu {
                ForEach(recents, id: \.path) { url in
                    Button {
                        dest = url
                        RecentDestinations.push(url, scope: .combine)
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
            // C22 — record on the combine-scope recents list.
            RecentDestinations.push(url, scope: .combine)
        }
    }

    private func retitleForPreset() {
        // Pick the file extension off the preset's declared one. C18
        // — audio-only (m4a) sits in the picker now, so the legacy
        // ProRes-vs-mp4 ternary isn't expressive enough.
        let ext = selectedPreset?.fileExtension ?? "mp4"
        let base = (filename as NSString).deletingPathExtension
        filename = base.isEmpty ? "combined.\(ext)" : "\(base).\(ext)"
    }

    private func runCombine() {
        guard let preset = selectedPreset, let dest else { return }
        let outURL = dest.appendingPathComponent(filename)
        // C16 — translate each row's trim text into the
        // CombineSource model. Empty / unparseable text falls back
        // to nil (= use the clip's natural start / end), keeping
        // the pre-C16 whole-clip path available without ceremony.
        let combineSources = rows.map { row in
            CombineSource(
                url: URL(fileURLWithPath: row.asset.path),
                trimInSeconds: parseTrim(row.trimInText),
                trimOutSeconds: parseTrim(row.trimOutText),
                sourceMarkers: preserveMarkers ? row.sourceMarkers : [],
                // C24 — empty text → nil (inherit global); a
                // parseable non-empty value → the per-pair override.
                crossfadeAfterSeconds: Double(row.crossfadeAfterText),
                // C36 — per-pair easing override; nil = inherit.
                crossfadeEasingAfter: row.crossfadeEasingAfter
            )
        }
        let j = CombineClipsJob(sources: combineSources,
                                 outputURL: outURL,
                                 preset: preset,
                                 dimensionMode: resolvedDimensionMode(),
                                 crossfadeSeconds: Double(crossfadeText) ?? 0,
                                 fadeFromBlackSeconds: Double(fadeFromBlackText) ?? 0,
                                 fadeToBlackSeconds: Double(fadeToBlackText) ?? 0,
                                 crossfadeEasing: crossfadeEasing)
        self.job = j
        Task {
            await j.run()
            // Reveal the file on success; leave the sheet open so
            // the user can read the result line.
            if case .finished(let url) = j.state {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                await appState.rescan()
                // C17 — write preserved markers against the freshly
                // catalogued output asset. Lookup runs after rescan
                // so the new row is in `asset`; if for any reason it
                // isn't (rescan filtered it, race), we just skip the
                // DB write rather than fail the whole combine.
                if let newAsset = try? appState.db.asset(forPath: url.path),
                   let newId = newAsset.rowId {
                    for m in j.preservedMarkers {
                        _ = try? appState.db.addMarker(
                            assetId: newId,
                            timecodeIn: m.timecodeIn,
                            timecodeOut: m.timecodeOut,
                            note: m.note
                        )
                    }
                }
            }
        }
    }

    /// Accept `HH:MM:SS`, `MM:SS`, or plain seconds; empty input
    /// returns nil so the row falls back to the clip's natural
    /// in/out. Same shape as `parseHHMMSS` in InlineFilterRow but
    /// kept local — these are small enough that sharing isn't worth
    /// the cross-view dependency.
    private func parseTrim(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":").map(String.init)
        switch parts.count {
        case 3:
            guard let h = Int(parts[0]), let m = Int(parts[1]),
                  let s = Double(parts[2]) else { return nil }
            return Double(h * 3600 + m * 60) + s
        case 2:
            guard let m = Int(parts[0]),
                  let s = Double(parts[1]) else { return nil }
            return Double(m * 60) + s
        case 1:
            return Double(parts[0])
        default:
            return nil
        }
    }

    /// C36 — short human-readable name for the per-row easing
    /// Menu. Mirrors the global picker's labels in the output-
    /// controls block.
    private func easingLabel(_ e: CrossfadeEasing) -> String {
        switch e {
        case .linear:    return "Linear"
        case .easeIn:    return "Ease In"
        case .easeOut:   return "Ease Out"
        case .easeInOut: return "Ease In-Out"
        }
    }

    private func durationLabel(_ asset: Asset) -> String {
        let s = asset.durationSeconds ?? 0
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
    /// Sums each row's effective duration (after applying trim) so
    /// the "Total: m:ss" readout reflects what'll actually render
    /// rather than the full source durations.
    private var totalDurationLabel: String {
        let total = Int(rows.reduce(0.0) { sum, row in
            let dur = row.asset.durationSeconds ?? 0
            let inS = parseTrim(row.trimInText) ?? 0
            let outS = parseTrim(row.trimOutText) ?? dur
            return sum + max(0, outS - inS)
        })
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
