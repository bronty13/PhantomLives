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
        .frame(width: 640, height: 580)
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
                Button("Choose…") { pickDest() }
            }
            HStack(spacing: 8) {
                Text("Filename:")
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
                TextField("", text: $filename)
                    .textFieldStyle(.roundedBorder)
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
                sourceMarkers: preserveMarkers ? row.sourceMarkers : []
            )
        }
        let j = CombineClipsJob(sources: combineSources,
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
