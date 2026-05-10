import SwiftUI
import AppKit

/// Walks a list of clips through the file audit one at a time. Shows the
/// same audit panel as the per-clip sheet (with rename suggestions, the
/// reduce-clip button, the "apply detected filenames" action) and adds a
/// progress bar + Skip / Next navigation. At the end it surfaces a summary
/// of clean / fixed / still-needs-work clips.
///
/// Triggered from the Editing Queue and Posting Queue toolbars. Uses the
/// queue's already-filtered clip list as input — pick a status filter on
/// the queue first if you want to narrow the workflow.
struct FileAuditWorkflow: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let clips: [Clip]

    /// When true, the workflow only steps through clips whose initial
    /// audit reported issues. Toggleable from the workflow header.
    @State private var onlyIssues: Bool = false
    /// IDs that had issues at workflow open. Computed once on appear so
    /// fixing a clip doesn't immediately drop it from the iteration —
    /// the user finishes it then advances.
    @State private var issueClipIds: Set<String> = []

    @State private var index: Int = 0
    @State private var skipped: Set<String> = []
    @State private var fixedDuringRun: Set<String> = []
    @State private var initiallyClean: Set<String> = []
    @State private var auditCache: [String: FileAuditService.Result] = [:]
    @State private var renameError: String?
    @State private var bulkProvisionRunning: Bool = false
    @State private var bulkProvisionMessage: String?
    @State private var bulkRestampRunning: Bool = false
    @State private var bulkRestampMessage: String?
    @State private var reducing: Bool = false
    @State private var reduceMessage: String?
    @State private var transcribing: Bool = false
    @State private var transcribeMessage: String?
    /// IDs of clips whose transcript we (re)generated during this run, used
    /// to flip the pill into a "Transcribed in this session" state without
    /// re-fetching from the DB.
    @State private var transcribedThisRun: Set<String> = []
    @State private var capturing: Bool = false
    @State private var captureMessage: String?
    @State private var hashing: Bool = false
    @State private var hashMessage: String?
    @State private var refining: Bool = false
    @State private var refineMessage: String?
    /// Per-clip picked frame number, owned by the workflow so it
    /// survives picker re-renders. Seeded from each clip's stored
    /// `thumbnailFilename` on entry; user clicks update this map and
    /// "Use as thumbnail" reads from it.
    @State private var pickedByClip: [String: Int] = [:]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if index < workingClips.count {
                clipPanel(workingClips[index])
            } else {
                summary
            }
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            preflightAuditAll()
            if let first = workingClips.first {
                runAudit(for: first, recordInitial: true)
            }
        }
        .onChange(of: onlyIssues) { _, _ in
            // Switching modes — clamp the index and re-audit the new
            // current clip so the panel reflects the right one.
            index = 0
            if let first = workingClips.first {
                runAudit(for: first, recordInitial: false)
            }
        }
    }

    /// The list the workflow actually steps through — either every
    /// clip the queue handed us, or only the ones whose preflight
    /// audit had issues.
    private var workingClips: [Clip] {
        onlyIssues ? clips.filter { issueClipIds.contains($0.id) } : clips
    }

    /// Quick pre-pass at workflow open — audit every clip, record its
    /// hasIssues state, and seed pickers. This lets the "issues only"
    /// toggle work without further DB hits and lets the summary report
    /// "initially clean" accurately.
    private func preflightAuditAll() {
        for clip in clips {
            let live = appState.clips.first { $0.id == clip.id } ?? clip
            let r = FileAuditService.audit(clip: live, settings: appState.settings)
            auditCache[live.id] = r
            seedPickedFrame(for: live, frames: r.foundFrameNumbers)
            if r.hasIssues {
                issueClipIds.insert(live.id)
            } else {
                initiallyClean.insert(live.id)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("File-verification workflow").font(.title3.weight(.semibold))
                Spacer()
                Picker("", selection: $onlyIssues) {
                    Text("All clips (\(clips.count))").tag(false)
                    Text("Only with issues (\(issueClipIds.count))").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
                .help("Toggle between every clip in the queue and only the ones whose initial audit had issues.")
                Text(progressText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                let candidates = clipsNeedingProductionFolder()
                let outOfPattern = clipsWithOutOfPatternProductionFolder()
                Button {
                    runBulkProvisionProduction()
                } label: {
                    if bulkProvisionRunning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Stamping…")
                        }
                    } else {
                        Label("Stamp \(candidates.count) missing production folder\(candidates.count == 1 ? "" : "s")",
                              systemImage: "folder.badge.plus")
                    }
                }
                .controlSize(.small)
                .disabled(candidates.isEmpty || bulkProvisionRunning)
                .help("For every clip in the queue with no production folder set, create `<base>/<contentDate> <Title>/` and (when an FCP MP4 candidate exists) copy it in as `Title.<ext>`. Single transaction per clip; failures are reported per row.")

                Button {
                    runBulkRestampProduction()
                } label: {
                    if bulkRestampRunning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Re-stamping…")
                        }
                    } else {
                        Label("Re-stamp \(outOfPattern.count) out-of-pattern folder\(outOfPattern.count == 1 ? "" : "s")",
                              systemImage: "folder.badge.gearshape")
                    }
                }
                .controlSize(.small)
                .disabled(outOfPattern.isEmpty || bulkRestampRunning)
                .help("Walk every clip whose stored production folder doesn't match the current pattern. mkdir -p the new `<base>/<contentDate> <Title>/` folder, copy the per-clip files (`Title.<ext>` and `Title_*.*`) from the old folder, then update the clip's path. Old folders are NOT deleted.")

                if let msg = bulkProvisionMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
                if let msg = bulkRestampMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            ProgressView(value: progressValue)
                .progressViewStyle(.linear)
        }
        .padding(16)
    }

    /// Subset of `clips` that look like good targets for the bulk
    /// provision-folder pass — no production folder set, but a content
    /// date and title are both available so the path is well-defined.
    private func clipsNeedingProductionFolder() -> [Clip] {
        clips.filter { c in
            (c.productionFolder ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                && !(c.contentDate ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                && !c.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Clips whose stored `production_folder` doesn't match what the
    /// current pattern resolves to. Driven off the same path resolver as
    /// the audit pill so the two stay in sync.
    private func clipsWithOutOfPatternProductionFolder() -> [Clip] {
        clips.filter { c in
            let stored = (c.productionFolder ?? "").trimmingCharacters(in: .whitespaces)
            guard !stored.isEmpty else { return false }
            guard let expected = PathDefaultsService.productionPath(
                for: c, settings: appState.settings
            ) else { return false }
            let lhs = (stored as NSString).expandingTildeInPath
                .precomposedStringWithCanonicalMapping
            let rhs = (expected as NSString).expandingTildeInPath
                .precomposedStringWithCanonicalMapping
            return lhs != rhs
        }
    }

    private func runBulkRestampProduction() {
        guard !bulkRestampRunning else { return }
        bulkRestampRunning = true
        bulkRestampMessage = "Re-stamping…"
        Task { @MainActor in
            let r = PathDefaultsService.restampOutOfPatternProductionFolders(appState: appState)
            bulkRestampRunning = false
            var pieces: [String] = ["Stamped \(r.stamped) of \(r.stamped + r.matched + r.failed.count + r.skippedNoExpected)"]
            if r.filesCopied > 0 { pieces.append("\(r.filesCopied) files copied") }
            if r.failed.count > 0 { pieces.append("\(r.failed.count) failed") }
            bulkRestampMessage = pieces.joined(separator: " · ")
            // Re-audit visible clips so the UI shows the new paths.
            for clip in clips {
                if let live = try? DatabaseService.shared.fetchClip(id: clip.id) {
                    runAudit(for: live, recordInitial: false)
                }
            }
        }
    }

    private func runBulkProvisionProduction() {
        guard !bulkProvisionRunning else { return }
        let baseTrim = appState.settings.defaultProductionBase.trimmingCharacters(in: .whitespaces)
        guard !baseTrim.isEmpty else {
            bulkProvisionMessage = "Production root not configured (Settings → File Locations)."
            return
        }
        let candidates = clipsNeedingProductionFolder()
        guard !candidates.isEmpty else {
            bulkProvisionMessage = "Nothing to stamp — no clips in this queue have a missing production folder."
            return
        }
        bulkProvisionRunning = true
        bulkProvisionMessage = "Stamping \(candidates.count) clip\(candidates.count == 1 ? "" : "s")…"
        Task {
            var ok = 0, copied = 0, failed = 0
            for clip in candidates {
                do {
                    let auditResult = FileAuditService.audit(clip: clip, settings: appState.settings)
                    let outcome = try FileAuditService.provisionProductionFolder(
                        clip: clip,
                        settings: appState.settings,
                        fcpSourceFilename: auditResult.fcpMp4Candidate
                    )
                    var mutated = clip
                    mutated.productionFolder = outcome.productionPath
                    if let canonical = outcome.canonicalFilename {
                        mutated.clipFilename = canonical
                        copied += 1
                    }
                    try appState.updateClip(mutated)
                    ok += 1
                } catch {
                    failed += 1
                }
            }
            bulkProvisionRunning = false
            var pieces: [String] = ["Stamped \(ok) of \(candidates.count)"]
            if copied > 0 { pieces.append("\(copied) with FCP copy") }
            if failed > 0 { pieces.append("\(failed) failed") }
            bulkProvisionMessage = pieces.joined(separator: " · ")
            // Re-audit visible clips so the UI reflects the new state.
            for clip in candidates {
                if let live = try? DatabaseService.shared.fetchClip(id: clip.id) {
                    runAudit(for: live, recordInitial: false)
                }
            }
        }
    }

    private var progressText: String {
        let total = workingClips.count
        if total == 0 { return "0 of 0" }
        if index >= total { return "\(total) of \(total)" }
        return "\(index + 1) of \(total)"
    }

    private var progressValue: Double {
        let total = workingClips.count
        guard total > 0 else { return 0 }
        return Double(min(index, total)) / Double(total)
    }

    // MARK: - Per-clip panel

    private func clipPanel(_ clip: Clip) -> some View {
        // Always render off the live AppState clip rather than the workflow's
        // input snapshot. The audit itself uses live state via runAudit, but
        // the row's pill conditions (canPushFromFCP, canShowCapture, prod path
        // for the capture pill, etc.) read fields like productionFolder /
        // clipFilename — if a parent passed in a stale draft (e.g. ClipEditView
        // opens with [draft] before its first save), the snapshot's empty
        // productionFolder kept the pills hidden even after the audit said
        // production was OK.
        let live = appState.clips.first(where: { $0.id == clip.id }) ?? clip
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                clipBanner(live)
                if let r = auditCache[live.id] {
                    summaryStats(r)
                    if !r.hasIssues {
                        allClearBanner(in: r)
                    }
                    ForEach(r.allChecks) { check in
                        rowView(check, for: live, in: r)
                    }
                } else {
                    ProgressView("Auditing…")
                        .padding(40)
                        .frame(maxWidth: .infinity)
                }
                if let msg = renameError {
                    pillBanner(msg, color: .red, icon: "exclamationmark.triangle.fill") {
                        renameError = nil
                    }
                }
                if let msg = reduceMessage {
                    pillBanner(msg, color: .indigo, icon: "info.circle.fill") {
                        reduceMessage = nil
                    }
                }
                if let msg = transcribeMessage {
                    pillBanner(msg, color: .teal, icon: "waveform") {
                        transcribeMessage = nil
                    }
                }
                if let msg = captureMessage {
                    pillBanner(msg, color: .pink, icon: "photo.on.rectangle") {
                        captureMessage = nil
                    }
                }
                if let msg = hashMessage {
                    pillBanner(msg, color: .indigo, icon: "function") {
                        hashMessage = nil
                    }
                }
                if let msg = refineMessage {
                    pillBanner(msg, color: .purple, icon: "wand.and.stars") {
                        refineMessage = nil
                    }
                }
            }
            .padding(16)
        }
    }

    private func clipBanner(_ clip: Clip) -> some View {
        HStack(spacing: 10) {
            PersonaPill(code: clip.personaCode)
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.title.isEmpty ? "Untitled clip" : clip.title)
                    .font(.headline)
                ClipIDLabel(id: clip.id, style: .captionSecondary)
            }
            Spacer()
            Button {
                appState.focusedClipId = clip.id
                appState.selectedSection = .clips
                dismiss()
            } label: {
                Label("Open in editor", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.borderless)
            .help("Close the workflow and jump into this clip's editor")
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func summaryStats(_ r: FileAuditService.Result) -> some View {
        HStack(spacing: 12) {
            Label("\(r.okCount) OK", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
            if r.warnCount > 0 {
                Label("\(r.warnCount) warning", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if r.missingCount > 0 {
                Label("\(r.missingCount) missing", systemImage: "questionmark.circle.fill")
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .font(.caption)
    }

    // MARK: - Row + actions

    private func rowView(_ check: FileAuditService.Check, for clip: Clip, in result: FileAuditService.Result) -> some View {
        let canReduce = check.id == result.reduced.id
            && check.status == .missing
            && result.mp4.path != nil
            && check.path != nil
        let isFramesRow = check.id == result.thumbnailFrames.id
        let canShowCapture = isFramesRow
            && (result.mp4.status == .ok || result.mp4.status == .warn)
            && result.production.status == .ok
        let canShowPicker = isFramesRow && !result.foundFrameNumbers.isEmpty
        let isTranscriptRow = check.id == result.transcript.id
            && result.mp4.path != nil
        let canPickFCP = check.id == result.fcp.id && check.status != .ok
        let isHashRow = check.id == result.hashes.id
            && (result.mp4.status == .ok || result.mp4.status == .warn)
        let canPushFromFCP = check.id == result.mp4.id
            && check.status == .missing
            && result.fcpMp4Candidate != nil
            && !(clip.productionFolder ?? "").isEmpty
        let canRefineDescription = check.id == result.description.id
            && check.status == .warn
        let canProvisionProduction = check.id == result.production.id
            && check.status != .ok
            && !(clip.contentDate ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            && !appState.settings.defaultProductionBase.trimmingCharacters(in: .whitespaces).isEmpty
            && !clip.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon(for: check.status))
                    .font(.title3)
                    .foregroundStyle(color(for: check.status))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(check.label).font(.body.weight(.medium))
                        if let size = check.sizeFormatted {
                            Text(size).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    Text(check.detail)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if let path = check.path, !path.isEmpty {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help(path)
                }
            }

            if let s = check.suggestedRename {
                renamePill(s, clipId: clip.id)
            }
            if canReduce, let src = result.mp4.path, let dst = check.path {
                reducePill(src: src, dst: dst, clipId: clip.id)
            }

            if canPushFromFCP, let candidate = result.fcpMp4Candidate {
                pushFromFCPPill(clipId: clip.id, candidate: candidate, title: clip.title)
            }

            if canProvisionProduction {
                provisionProductionFolderPill(
                    clip: clip,
                    candidate: result.fcpMp4Candidate
                )
            }

            if canRefineDescription {
                refineDescriptionPill(clipId: clip.id)
            }

            if isTranscriptRow, let src = result.mp4.path {
                transcribePill(src: src,
                               clipId: clip.id,
                               alreadyHas: check.status == .ok)
            }

            if canPickFCP {
                fcpPickerPill(clipId: clip.id)
            }

            if isHashRow {
                hashPill(clipId: clip.id, status: check.status)
            }

            // Thumbnail-frames row: capture FIRST (creates the source),
            // then picker (selects from it).
            if canShowCapture,
               let src = result.mp4.path,
               let prod = clip.productionFolder.flatMap({ ($0 as NSString).expandingTildeInPath }) {
                capturePill(clipId: clip.id,
                            src: src,
                            prod: prod,
                            n: max(1, appState.settings.numFramesToCapture),
                            status: result.thumbnailFrames.status)
            }

            if canShowPicker {
                let live = appState.clips.first { $0.id == clip.id } ?? clip
                ThumbnailFramePicker(
                    title: clip.title,
                    productionFolder: clip.productionFolder,
                    foundFrameNumbers: result.foundFrameNumbers,
                    currentSelection: live.thumbnailFilename,
                    picked: pickedBinding(for: clip.id, fallback: result.foundFrameNumbers.first ?? 1)
                ) { newFilename in
                    pickThumbnail(newFilename, for: clip.id)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color(for: check.status).opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(color(for: check.status).opacity(0.35), lineWidth: 1))
    }

    /// Promote the picked frame to be this clip's thumbnail. Copies
    /// frame bytes to `<Title>.png` in Production, cleans up any stale
    /// `<Title>.png` mirror in FCP, and stores the FRAME's filename on
    /// `clip.thumbnailFilename` so the picker remembers which one was
    /// picked next time and the editor can show it.
    ///
    /// We deliberately re-read the picked frame from `pickedByClip`
    /// rather than trusting the filename string the picker passed in —
    /// that way "what got saved" exactly matches "what's highlighted"
    /// even if SwiftUI re-renders mid-click.
    private func pickThumbnail(_ frameFilename: String, for clipId: String) {
        guard let live = appState.clips.first(where: { $0.id == clipId }) else {
            renameError = "Couldn't reload the clip — close and reopen the workflow."
            return
        }
        guard let prod = live.productionFolder, !prod.isEmpty else {
            renameError = "Production folder isn't set — can't promote the frame."
            return
        }
        // Authoritative filename = the value the parent has persisted
        // for this clip's picker. Fall back to the picker-supplied
        // filename if the dict didn't get seeded for some reason.
        let n = pickedByClip[clipId]
        let canonicalFrameName = n.map {
            String(format: "%@_frame_%02d.png", live.title, $0)
        } ?? frameFilename
        do {
            _ = try FileAuditService.promoteFrameToThumbnail(
                productionFolder: prod,
                fcpFolder: live.fcpProjectFolder,
                title: live.title,
                frameFilename: canonicalFrameName
            )
            var updated = live
            updated.thumbnailFilename = canonicalFrameName
            try appState.updateClip(updated)
            clearAllMessages()
            if let idx = clips.firstIndex(where: { $0.id == clipId }) {
                runAudit(for: clips[idx], recordInitial: false)
            }
        } catch {
            renameError = "Couldn't promote frame: \(error.localizedDescription)"
        }
    }

    /// Wipe every banner so a successful action can present a clean
    /// "all green" audit panel instead of leaving stale info / error
    /// messages around from earlier attempts.
    private func clearAllMessages() {
        renameError = nil
        reduceMessage = nil
        transcribeMessage = nil
        captureMessage = nil
        hashMessage = nil
        refineMessage = nil
    }

    private func renamePill(_ s: FileAuditService.SuggestedRename, clipId: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.rays")
                    .font(.caption).foregroundStyle(.purple)
                Text("Rename to fix")
                    .font(.caption.weight(.semibold)).foregroundStyle(.purple)
                Spacer()
                Button {
                    applyRename(s, for: clipId)
                } label: {
                    Label("Rename", systemImage: "arrow.triangle.2.circlepath")
                }
                .controlSize(.small)
                .help("\(s.currentFilename) → \(s.targetFilename)")
            }
            HStack(spacing: 6) {
                Text(s.currentFilename).font(.caption.monospaced()).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                Text(s.targetFilename).font(.caption.monospaced())
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.purple.opacity(0.25), lineWidth: 1))
    }

    /// Inline pill on the missing-Main-MP4 row when an MP4 was found in
    /// the FCP folder. Move it into Production with the canonical name,
    /// re-audit so the row turns green.
    private func pushFromFCPPill(clipId: String, candidate: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.square")
                    .font(.caption).foregroundStyle(.green)
                Text("Push rendered MP4 from FCP")
                    .font(.caption.weight(.semibold)).foregroundStyle(.green)
                Spacer()
                Button {
                    runPushFromFCP(clipId: clipId, candidate: candidate)
                } label: {
                    Label("Push", systemImage: "arrow.right.square")
                }
                .controlSize(.small)
            }
            HStack(spacing: 6) {
                Text(candidate).font(.caption.monospaced()).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                Text("\(title).mp4").font(.caption.monospaced())
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.green.opacity(0.25), lineWidth: 1))
    }

    /// Inline "Create production folder" pill on the Production row when
    /// the folder is missing. Folder layout = `<base>/<contentDate>` per
    /// the user's stated convention. With a candidate the pill copies
    /// `<fcp>/<candidate>` → `<prod>/<sanitizedTitle>.<ext>` in one call.
    private func provisionProductionFolderPill(
        clip: Clip,
        candidate: String?
    ) -> some View {
        let willCopy = candidate != nil
        let titleSafe = clip.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ext = (candidate.map { ($0 as NSString).pathExtension } ?? "")
        let destFilename = ext.isEmpty ? titleSafe : "\(titleSafe).\(ext)"
        // Same resolution as provisionProductionFolder so preview = reality.
        let plannedPath = PathDefaultsService.productionPath(
            for: clip,
            settings: appState.settings
        ) ?? "(set the production root in Settings → File Locations)"
        let clipId = clip.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .font(.caption).foregroundStyle(.blue)
                Text(willCopy
                     ? "Create production folder + copy from FCP"
                     : "Create production folder")
                    .font(.caption.weight(.semibold)).foregroundStyle(.blue)
                Spacer()
                Button {
                    runProvisionProductionFolder(clipId: clipId, candidate: candidate)
                } label: {
                    Label(willCopy ? "Create + copy" : "Create",
                          systemImage: "folder.badge.plus")
                }
                .controlSize(.small)
            }
            HStack(spacing: 6) {
                Text(plannedPath).font(.caption.monospaced()).foregroundStyle(.secondary)
                if willCopy {
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                    Text(destFilename).font(.caption.monospaced())
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.blue.opacity(0.25), lineWidth: 1))
    }

    private func runProvisionProductionFolder(clipId: String, candidate: String?) {
        do {
            guard let live = try DatabaseService.shared.fetchClip(id: clipId) else {
                renameError = "Couldn't reload the clip."
                return
            }
            let outcome = try FileAuditService.provisionProductionFolder(
                clip: live,
                settings: appState.settings,
                fcpSourceFilename: candidate
            )
            var mutated = live
            mutated.productionFolder = outcome.productionPath
            if let canonical = outcome.canonicalFilename {
                mutated.clipFilename = canonical
            }
            try appState.updateClip(mutated)
            clearAllMessages()
            if let idx = clips.firstIndex(where: { $0.id == clipId }) {
                runAudit(for: clips[idx], recordInitial: false)
            }
        } catch {
            renameError = "Provision failed: \(error.localizedDescription)"
        }
    }

    private func runPushFromFCP(clipId: String, candidate: String) {
        do {
            guard let live = appState.clips.first(where: { $0.id == clipId }),
                  let fcp = live.fcpProjectFolder, !fcp.isEmpty,
                  let prod = live.productionFolder, !prod.isEmpty else {
                renameError = "Both the FCP and Production folder paths must be set."
                return
            }
            _ = try FileAuditService.pushFromFCP(
                fcpFolder: fcp,
                productionFolder: prod,
                title: live.title,
                sourceFilename: candidate
            )
            clearAllMessages()
            if let idx = clips.firstIndex(where: { $0.id == clipId }) {
                runAudit(for: clips[idx], recordInitial: false)
            }
        } catch {
            renameError = "Push failed: \(error.localizedDescription)"
        }
    }

    /// Inline refine pill on the Description (raw only) audit row.
    /// Streams Ollama and persists `descriptionRefined`.
    private func refineDescriptionPill(clipId: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.caption).foregroundStyle(.purple)
            Text("Refine raw description via Ollama")
                .font(.caption.weight(.semibold)).foregroundStyle(.purple)
            Spacer()
            Button {
                runRefine(clipId: clipId)
            } label: {
                if refining {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Refining…")
                    }
                } else {
                    Label("Refine", systemImage: "wand.and.stars")
                }
            }
            .controlSize(.small)
            .disabled(refining)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.purple.opacity(0.25), lineWidth: 1))
    }

    private func runRefine(clipId: String) {
        guard !refining else { return }
        refining = true
        refineMessage = nil
        let template = appState.settings.refinePromptTemplate
        let model = appState.settings.ollamaModel
        let baseURL = appState.settings.ollamaBaseURL
        Task {
            do {
                guard let live = try DatabaseService.shared.fetchClip(id: clipId) else {
                    refineMessage = "Couldn't reload the clip."
                    refining = false
                    return
                }
                var accumulated = ""
                try await OllamaService.refine(
                    description: live.descriptionRaw,
                    promptTemplate: template,
                    model: model,
                    baseURLString: baseURL,
                    onToken: { token in accumulated += token }
                )
                let cleaned = OllamaService.cleanRefineOutput(accumulated)
                if var updated = try DatabaseService.shared.fetchClip(id: clipId) {
                    updated.descriptionRefined = cleaned
                    let stamp = "[Refined \(DatabaseService.isoDate(Date()))]"
                    if !updated.notes.contains(stamp) {
                        updated.notes = updated.notes.isEmpty
                            ? stamp
                            : updated.notes + "\n" + stamp
                    }
                    try appState.updateClip(updated)
                }
                refining = false
                clearAllMessages()
                if let idx = clips.firstIndex(where: { $0.id == clipId }) {
                    runAudit(for: clips[idx], recordInitial: false)
                }
            } catch {
                refining = false
                refineMessage = "Refine failed: \(error.localizedDescription)"
            }
        }
    }

    /// Inline hash-action pill on the File hashes audit row.
    private func hashPill(clipId: String, status: FileAuditService.CheckStatus) -> some View {
        let pillColor: Color = {
            switch status {
            case .missing: return .red
            case .warn:    return .orange
            case .ok:      return .gray
            case .na:      return .gray
            }
        }()
        return HStack(spacing: 8) {
            Image(systemName: "function")
                .font(.caption).foregroundStyle(pillColor)
            Text(status == .ok ? "Hashes already on file" : "Compute MD5 / SHA-1 / SHA-256")
                .font(.caption.weight(.semibold))
                .foregroundStyle(pillColor)
            Spacer()
            Button {
                runHash(clipId: clipId)
            } label: {
                if hashing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Hashing…")
                    }
                } else if status == .ok {
                    Label("Re-compute", systemImage: "arrow.clockwise")
                } else {
                    Label("Compute", systemImage: "function")
                }
            }
            .controlSize(.small)
            .disabled(hashing)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pillColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(pillColor.opacity(0.25), lineWidth: 1))
    }

    private func runHash(clipId: String) {
        guard !hashing else { return }
        hashing = true
        hashMessage = nil
        Task {
            do {
                guard let live = appState.clips.first(where: { $0.id == clipId }),
                      let prod = live.productionFolder, !prod.isEmpty,
                      !live.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    hashMessage = "Set the production folder + title first."
                    hashing = false
                    return
                }
                let expanded = (prod as NSString).expandingTildeInPath
                let mainPath = (expanded as NSString)
                    .appendingPathComponent(live.title + ".mp4")
                let reducedPath = (expanded as NSString)
                    .appendingPathComponent(live.title + "_reduced.mp4")

                let main = try await HashService.hash(filePath: mainPath)
                let reduced: HashService.Hashes? = await {
                    guard FileManager.default.fileExists(atPath: reducedPath) else { return nil }
                    return try? await HashService.hash(filePath: reducedPath)
                }()

                var updated = live
                updated.mp4Md5         = main.md5
                updated.mp4Sha1        = main.sha1
                updated.mp4Sha256      = main.sha256
                updated.mp4SizeBytes   = main.sizeBytes
                if let r = reduced {
                    updated.reducedMd5        = r.md5
                    updated.reducedSha1       = r.sha1
                    updated.reducedSha256     = r.sha256
                    updated.reducedSizeBytes  = r.sizeBytes
                } else {
                    updated.reducedMd5 = ""
                    updated.reducedSha1 = ""
                    updated.reducedSha256 = ""
                    updated.reducedSizeBytes = nil
                }
                updated.hashesComputedAt = DatabaseService.isoNow()
                try appState.updateClip(updated)
                hashing = false
                clearAllMessages()
                if let idx = clips.firstIndex(where: { $0.id == clipId }) {
                    runAudit(for: clips[idx], recordInitial: false)
                }
            } catch {
                hashing = false
                hashMessage = "Hash failed: \(error.localizedDescription)"
            }
        }
    }

    /// Inline FCP-picker pill on the FCP-folder audit row when the path
    /// isn't set or the volume isn't reachable. NSOpenPanel for folder
    /// selection, persists the result onto the clip, re-audits.
    private func fcpPickerPill(clipId: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.badge.gearshape")
                .font(.caption).foregroundStyle(.blue)
            Text("Set the FCP project folder")
                .font(.caption.weight(.semibold)).foregroundStyle(.blue)
            Spacer()
            Button {
                pickFCPFolder(clipId: clipId)
            } label: {
                Label("Choose…", systemImage: "folder")
            }
            .controlSize(.small)
            .help("Pick the folder that contains this clip's `<Title>.fcpbundle`.")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.blue.opacity(0.25), lineWidth: 1))
    }

    private func pickFCPFolder(clipId: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        panel.message = "Pick the folder containing this clip's `<Title>.fcpbundle`."
        if let live = appState.clips.first(where: { $0.id == clipId }),
           let p = live.fcpProjectFolder?.trimmingCharacters(in: .whitespaces),
           !p.isEmpty {
            let expanded = (p as NSString).expandingTildeInPath
            panel.directoryURL = URL(fileURLWithPath: expanded)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            if var live = appState.clips.first(where: { $0.id == clipId }) {
                // Standardised path: handles trailing-slash + Unicode
                // normalisation so `fileExists(atPath:)` matches the
                // volume's canonical name on subsequent re-audits.
                live.fcpProjectFolder = url.standardizedFileURL.path
                try appState.updateClip(live)
                clearAllMessages()
                if let idx = clips.firstIndex(where: { $0.id == clipId }) {
                    runAudit(for: clips[idx], recordInitial: false)
                }
            }
        } catch {
            renameError = "Couldn't save FCP folder: \(error.localizedDescription)"
        }
    }

    /// Combined transcript-action pill — lives on the Video transcription
    /// audit row whether the transcript already exists or not. Becomes
    /// "Re-generate" once a transcript is on file so the action is
    /// always available without a separate pill at the bottom.
    private func transcribePill(src: String, clipId: String, alreadyHas: Bool) -> some View {
        let scriptAvailable = TranscriptionService.locateScript() != nil
        let pillColor: Color = alreadyHas ? .gray : .teal
        return HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.caption).foregroundStyle(pillColor)
            Text(alreadyHas ? "Transcript already on file" : "Run a whisper transcript")
                .font(.caption.weight(.semibold))
                .foregroundStyle(pillColor)
            Spacer()
            Button {
                runTranscribe(clipId: clipId, sourcePath: src)
            } label: {
                if transcribing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Transcribing…")
                    }
                } else if alreadyHas {
                    Label("Re-generate", systemImage: "arrow.clockwise")
                } else {
                    Label("Generate", systemImage: "waveform")
                }
            }
            .controlSize(.small)
            .disabled(transcribing || !scriptAvailable)
            .help(scriptAvailable
                  ? "Run sibling transcribe.py against \((src as NSString).lastPathComponent) and save the transcript onto this clip."
                  : "transcribe.py not found at ~/Documents/GitHub/PhantomLives/transcribe/ — install it first.")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pillColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(pillColor.opacity(0.25), lineWidth: 1))
    }

    /// Inline capture pill, on the thumbnail-frames row above the picker.
    private func capturePill(clipId: String, src: String, prod: String, n: Int, status: FileAuditService.CheckStatus) -> some View {
        let pillColor: Color = {
            switch status {
            case .missing: return .red
            case .warn:    return .orange
            case .ok:      return .secondary
            case .na:      return .secondary
            }
        }()
        let label: String = {
            switch status {
            case .missing: return "Capture \(n) thumbnails"
            case .warn:    return "Some frames missing — re-capture to fill"
            case .ok:      return "All \(n) frames captured"
            case .na:      return "Capture \(n) thumbnails"
            }
        }()
        return HStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle")
                .font(.caption).foregroundStyle(pillColor)
            Text(label)
                .font(.caption.weight(.semibold)).foregroundStyle(pillColor)
            Spacer()
            Button {
                if let live = appState.clips.first(where: { $0.id == clipId }) {
                    runCapture(clipId: clipId,
                               sourcePath: src,
                               productionFolder: prod,
                               title: live.title,
                               n: n)
                }
            } label: {
                if capturing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Capturing…")
                    }
                } else if status == .ok {
                    Label("Re-capture", systemImage: "arrow.clockwise")
                } else {
                    Label("Capture", systemImage: "camera")
                }
            }
            .controlSize(.small)
            .disabled(capturing)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pillColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(pillColor.opacity(0.25), lineWidth: 1))
    }

    /// "All checks passed" banner shown when nothing needs attention.
    private func allClearBanner(in r: FileAuditService.Result) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("All checks passed")
                    .font(.title3.weight(.semibold))
                Text("\(r.allChecks.count) of \(r.allChecks.count) clean — nothing needs attention on this clip.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.green.opacity(0.45), lineWidth: 1))
    }

    private func reducePill(src: String, dst: String, clipId: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.caption).foregroundStyle(.indigo)
            Text("Generate a smaller version")
                .font(.caption.weight(.semibold)).foregroundStyle(.indigo)
            Spacer()
            Button {
                runReduce(src: src, dst: dst, clipId: clipId)
            } label: {
                if reducing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Reducing…")
                    }
                } else {
                    Label("Reduce now", systemImage: "arrow.down.right.and.arrow.up.left")
                }
            }
            .controlSize(.small)
            .disabled(reducing)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.indigo.opacity(0.25), lineWidth: 1))
    }

    /// Action pill rendered under the audit rows. Only visible when the
    /// main MP4 is actually on disk (status `.ok` or `.warn`) — there's
    /// nothing to transcribe when the file is missing. Shows different
    /// labels depending on whether the clip already has a transcript.
    @ViewBuilder
    private func transcriptPill(for clip: Clip, in result: FileAuditService.Result) -> some View {
        let mp4Status = result.mp4.status
        let mp4Available = mp4Status == .ok || mp4Status == .warn
        let scriptAvailable = TranscriptionService.locateScript() != nil

        if mp4Available, let src = result.mp4.path {
            let live = appState.clips.first { $0.id == clip.id } ?? clip
            let alreadyHas = !live.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let regenerated = transcribedThisRun.contains(clip.id)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.caption).foregroundStyle(.teal)
                    Text(alreadyHas
                         ? (regenerated ? "Transcript regenerated this run" : "Transcript already on file")
                         : "Generate a whisper transcript")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.teal)
                    Spacer()
                    Button {
                        runTranscribe(clipId: clip.id, sourcePath: src)
                    } label: {
                        if transcribing {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Transcribing…")
                            }
                        } else if alreadyHas {
                            Label("Re-generate", systemImage: "arrow.clockwise")
                        } else {
                            Label("Generate", systemImage: "waveform")
                        }
                    }
                    .controlSize(.small)
                    .disabled(transcribing || !scriptAvailable)
                    .help(scriptAvailable
                          ? "Run sibling transcribe.py against \((src as NSString).lastPathComponent) and save the transcript to this clip."
                          : "transcribe.py not found at ~/Documents/GitHub/PhantomLives/transcribe/ — install it first.")
                }
                if !scriptAvailable {
                    Text("transcribe.py is missing — install the sibling project to enable this.")
                        .font(.caption2).foregroundStyle(.tertiary)
                } else if alreadyHas {
                    Text("\(wordCount(live.transcript)) words on file. Re-generating overwrites the existing transcript.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.teal.opacity(0.25), lineWidth: 1))
        }
    }

    private func wordCount(_ s: String) -> Int {
        s.split(whereSeparator: \.isWhitespace).count
    }

    /// Capture-thumbnails pill. Color tracks the thumbnail-frames audit
    /// status: red when none captured (error), orange when partial,
    /// muted secondary when all frames are already in place. The action
    /// label collapses to "Re-capture" once the row is green so the
    /// affordance survives but the visual emphasis goes away.
    @ViewBuilder
    private func capturePill(for clip: Clip, in result: FileAuditService.Result) -> some View {
        let mp4Status = result.mp4.status
        let mp4Available = mp4Status == .ok || mp4Status == .warn
        let prodReady    = result.production.status == .ok
        let n = max(1, appState.settings.numFramesToCapture)

        if mp4Available, prodReady, let src = result.mp4.path,
           let prod = (clip.productionFolder.flatMap { (($0 as NSString).expandingTildeInPath) }) {
            let pillColor = capturePillColor(for: result.thumbnailFrames.status)
            let label = capturePillLabel(for: result.thumbnailFrames.status, n: n)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.caption).foregroundStyle(pillColor)
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(pillColor)
                    Spacer()
                    Button {
                        runCapture(clipId: clip.id, sourcePath: src, productionFolder: prod, title: clip.title, n: n)
                    } label: {
                        if capturing {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Capturing…")
                            }
                        } else if result.thumbnailFrames.status == .ok {
                            Label("Re-capture", systemImage: "arrow.clockwise")
                        } else {
                            Label("Capture", systemImage: "camera")
                        }
                    }
                    .controlSize(.small)
                    .disabled(capturing)
                }
                Text("Frame 1 is sampled from the 1–9 s window so it usually catches the title card. Frames 2–\(n) are evenly distributed across the rest of the clip. All \(n) write to `\(clip.title)_frame_NN.png` in the production folder; existing files of the same name are overwritten.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(pillColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(pillColor.opacity(0.25), lineWidth: 1))
        }
    }

    private func capturePillColor(for status: FileAuditService.CheckStatus) -> Color {
        switch status {
        case .missing: return .red
        case .warn:    return .orange
        case .ok:      return .secondary
        case .na:      return .secondary
        }
    }

    private func capturePillLabel(for status: FileAuditService.CheckStatus, n: Int) -> String {
        switch status {
        case .missing: return "Capture \(n) thumbnails"
        case .warn:    return "Some frames missing — re-capture to fill"
        case .ok:      return "All \(n) frames captured"
        case .na:      return "Capture \(n) thumbnails"
        }
    }

    private func pillBanner(_ msg: String, color: Color, icon: String, dismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text(msg).font(.caption).foregroundStyle(color)
            Spacer()
            Button("Dismiss", action: dismiss)
                .buttonStyle(.borderless).controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Stop workflow") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button {
                goBack()
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(index == 0)
            .help("Go back to the previous clip and continue auditing it.")
            if index < workingClips.count {
                Button("Skip") {
                    skipped.insert(workingClips[index].id)
                    advance()
                }
                Button(index == workingClips.count - 1 ? "Finish" : "Next") {
                    advance()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            } else {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    /// Step back one clip in the working list, capturing any in-progress
    /// fixes on the current clip first. Skipped/initially-clean tracking
    /// stays intact so the summary still reflects the user's choices.
    private func goBack() {
        guard index > 0 else { return }
        if index < workingClips.count {
            let cur = workingClips[index]
            let r = FileAuditService.audit(clip: cur, settings: appState.settings)
            auditCache[cur.id] = r
        }
        clearAllMessages()
        if index - 1 >= 0 {
            skipped.remove(workingClips[index - 1].id)
        }
        index -= 1
        runAudit(for: workingClips[index], recordInitial: false)
    }

    // MARK: - Summary

    private var summary: some View {
        let cleanThisRun = (initiallyClean.union(fixedDuringRun))
            .subtracting(skipped)
        let stillBroken = workingClips
            .map(\.id)
            .filter { !cleanThisRun.contains($0) && !skipped.contains($0) }
        let issuesRemain = stillBroken.compactMap { id in workingClips.first(where: { $0.id == id }) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Workflow complete").font(.title2.weight(.semibold))
                Text("\(workingClips.count) clip\(workingClips.count == 1 ? "" : "s") audited.")
                    .font(.callout).foregroundStyle(.secondary)

                summaryStat(label: "Initially clean",
                            count: initiallyClean.count,
                            color: .green,
                            systemImage: "checkmark.seal.fill")
                summaryStat(label: "Fixed during workflow",
                            count: fixedDuringRun.subtracting(initiallyClean).count,
                            color: .blue,
                            systemImage: "wand.and.rays")
                summaryStat(label: "Skipped",
                            count: skipped.count,
                            color: .secondary,
                            systemImage: "forward.fill")
                summaryStat(label: "Still has issues",
                            count: issuesRemain.count,
                            color: .orange,
                            systemImage: "exclamationmark.triangle.fill")

                if !issuesRemain.isEmpty {
                    Divider().padding(.vertical, 6)
                    Text("Still needs work").font(.headline)
                    ForEach(issuesRemain) { clip in
                        Button {
                            appState.focusedClipId = clip.id
                            appState.selectedSection = .clips
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                PersonaPill(code: clip.personaCode)
                                Text(clip.title.isEmpty ? "Untitled" : clip.title)
                                    .font(.body.weight(.medium))
                                Spacer()
                                Text(clip.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                                Image(systemName: "arrow.up.right.square").foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.background, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryStat(label: String, count: Int, color: Color, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(color)
            Text(label).font(.body)
            Spacer()
            Text("\(count)")
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
        }
    }

    // MARK: - Actions

    private func advance() {
        // Re-evaluate the currently-shown clip's audit so we capture
        // changes the user just made (rename, reduce, etc.).
        if index < workingClips.count {
            let clip = workingClips[index]
            let r = FileAuditService.audit(clip: clip, settings: appState.settings)
            auditCache[clip.id] = r
            if !r.hasIssues {
                fixedDuringRun.insert(clip.id)
            }
        }
        renameError = nil
        reduceMessage = nil
        index += 1
        if index < workingClips.count {
            runAudit(for: workingClips[index], recordInitial: false)
        }
    }

    private func runAudit(for clip: Clip, recordInitial: Bool) {
        // Use the live clip from AppState so any post-action mutation
        // (transcript, thumbnailFilename, …) is reflected — the
        // workflow's `clips` array is a snapshot from when the sheet
        // opened and would otherwise keep showing stale "missing"
        // states for fields we just filled in.
        let live = appState.clips.first { $0.id == clip.id } ?? clip
        let r = FileAuditService.audit(clip: live, settings: appState.settings)
        auditCache[live.id] = r
        seedPickedFrame(for: live, frames: r.foundFrameNumbers)
        if recordInitial && !r.hasIssues {
            initiallyClean.insert(live.id)
        }
    }

    /// Seed `pickedByClip[live.id]` from the clip's stored
    /// `thumbnailFilename` if we haven't already (one-shot per clip).
    /// Falls back to the lowest found frame number when the stored
    /// filename doesn't match the `<Title>_frame_NN.png` pattern.
    private func seedPickedFrame(for live: Clip, frames: [Int]) {
        guard pickedByClip[live.id] == nil else { return }
        if let filename = live.thumbnailFilename,
           let n = ThumbnailFramePicker.parseFrameNumber(from: filename, title: live.title),
           frames.contains(n) {
            pickedByClip[live.id] = n
        } else if let first = frames.first {
            pickedByClip[live.id] = first
        }
    }

    /// Returns a binding into the per-clip pickedByClip dict so the
    /// picker can write directly. Reads return the seeded value; if the
    /// clip somehow isn't seeded yet, the supplied fallback is used.
    private func pickedBinding(for clipId: String, fallback: Int) -> Binding<Int> {
        Binding(
            get: { pickedByClip[clipId] ?? fallback },
            set: { pickedByClip[clipId] = $0 }
        )
    }

    private func applyRename(_ s: FileAuditService.SuggestedRename, for clipId: String) {
        do {
            try FileAuditService.applyRename(s)
            clearAllMessages()
            if let idx = clips.firstIndex(where: { $0.id == clipId }) {
                runAudit(for: clips[idx], recordInitial: false)
            }
        } catch {
            renameError = "Rename failed: \(error.localizedDescription)"
        }
    }

    /// Shells out to transcribe.py, persists the transcript onto the clip
    /// row, and surfaces a status message in the inline banner. The
    /// workflow's clip array is a snapshot — to keep the rest of the UI
    /// consistent we update via AppState so the editor shows the new
    /// transcript when the user navigates there from the summary.
    private func runTranscribe(clipId: String, sourcePath: String) {
        guard !transcribing else { return }
        transcribing = true
        transcribeMessage = nil
        Task {
            do {
                let outcome = try await TranscriptionService.transcribe(sourcePath: sourcePath)
                if var clip = appState.clips.first(where: { $0.id == clipId }) {
                    clip.transcript = outcome.transcript
                    try appState.updateClip(clip)
                }
                transcribedThisRun.insert(clipId)
                transcribing = false
                clearAllMessages()
                if let idx = clips.firstIndex(where: { $0.id == clipId }) {
                    runAudit(for: clips[idx], recordInitial: false)
                }
            } catch {
                transcribing = false
                transcribeMessage = "Transcribe failed: \(error.localizedDescription)"
            }
        }
    }

    private func runCapture(clipId: String, sourcePath: String, productionFolder: String, title: String, n: Int) {
        guard !capturing else { return }
        capturing = true
        captureMessage = nil
        Task {
            do {
                let outcome = try await FrameCaptureService.capture(
                    sourcePath: sourcePath,
                    productionFolder: productionFolder,
                    title: title,
                    numFrames: n
                )
                capturing = false
                clearAllMessages()
                if let idx = clips.firstIndex(where: { $0.id == clipId }) {
                    runAudit(for: clips[idx], recordInitial: false)
                }
            } catch {
                capturing = false
                captureMessage = "Capture failed: \(error.localizedDescription)"
            }
        }
    }

    private func runReduce(src: String, dst: String, clipId: String) {
        guard !reducing else { return }
        reducing = true
        reduceMessage = nil
        let threshold = Int64(appState.settings.largeFileThresholdMB) * 1024 * 1024
        Task {
            do {
                let outcome = try await ClipReduceService.reduce(
                    sourcePath: src, outputPath: dst, thresholdBytes: threshold
                )
                reducing = false
                clearAllMessages()
                _ = outcome
                if let idx = clips.firstIndex(where: { $0.id == clipId }) {
                    runAudit(for: clips[idx], recordInitial: false)
                }
            } catch {
                reducing = false
                reduceMessage = "Reduce failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Style

    private func icon(for status: FileAuditService.CheckStatus) -> String {
        switch status {
        case .ok:      return "checkmark.seal.fill"
        case .warn:    return "exclamationmark.triangle.fill"
        case .missing: return "questionmark.circle.fill"
        case .na:      return "minus.circle"
        }
    }

    private func color(for status: FileAuditService.CheckStatus) -> Color {
        switch status {
        case .ok:      return .green
        case .warn:    return .orange
        case .missing: return .red
        case .na:      return .secondary
        }
    }
}
