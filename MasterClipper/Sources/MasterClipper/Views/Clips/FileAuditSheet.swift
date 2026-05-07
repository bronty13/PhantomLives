import SwiftUI
import AppKit

/// Modal sheet that displays the results of `FileAuditService.audit(...)` for
/// a single clip. Each check row shows a status icon, the human-readable
/// label, the detail string, and (when applicable) the file size + a Reveal
/// button to open the path in Finder.
///
/// "Apply detected filenames" copies whatever filenames were actually found
/// on disk back into the clip's `clipFilename` / `thumbnailFilename` /
/// `previewFilename` columns — useful when the editor's filename fields are
/// blank or stale. Re-run uses the live (possibly edited) clip values.
struct FileAuditSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let clip: Clip
    var onApplyDetections: (FileAuditService.Result) -> Void

    @State private var result: FileAuditService.Result?
    @State private var lastRunAt: Date = Date()
    @State private var renameError: String?
    @State private var reducing: Bool = false
    @State private var reduceMessage: String?
    @State private var transcribing: Bool = false
    @State private var transcribeMessage: String?
    @State private var capturing: Bool = false
    @State private var captureMessage: String?
    @State private var hashing: Bool = false
    @State private var hashMessage: String?
    @State private var refining: Bool = false
    @State private var refineMessage: String?
    /// Currently-picked frame number for the thumbnail picker. Owned by
    /// the sheet so it survives re-renders triggered by re-audits.
    /// Seeded once from `clip.thumbnailFilename` on first audit.
    @State private var pickedFrame: Int = 1
    @State private var pickedSeeded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                if let r = result {
                    VStack(alignment: .leading, spacing: 8) {
                        if !r.hasIssues {
                            allClearBanner(in: r)
                        }
                        ForEach(r.allChecks) { check in
                            row(check, in: r)
                        }
                    }
                    .padding(16)
                } else {
                    ProgressView("Auditing…").padding(40).frame(maxWidth: .infinity)
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear { runAudit() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("File audit")
                    .font(.title3.weight(.semibold))
                Text(clip.title.isEmpty ? "Untitled clip" : clip.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let r = result {
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
                    }
                    .font(.caption)
                }
            }
            Spacer()
            Button {
                runAudit()
            } label: {
                Label("Re-run", systemImage: "arrow.clockwise")
            }
        }
        .padding(16)
    }

    // MARK: - Row

    private func row(_ check: FileAuditService.Check, in result: FileAuditService.Result) -> some View {
        let canReduce = check.id == result.reduced.id
            && check.status == .missing
            && result.mp4.path != nil
            && (check.path != nil)
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
            && check.status == .warn   // raw present, refined empty
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
                    .frame(width: 22, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(check.label).font(.body.weight(.medium))
                        if let size = check.sizeFormatted {
                            Text(size)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(check.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

            if let suggestion = check.suggestedRename {
                renameSuggestion(suggestion)
            }

            if canReduce, let src = result.mp4.path, let dst = check.path {
                reduceAction(src: src, dst: dst)
            }

            if canPushFromFCP, let candidate = result.fcpMp4Candidate {
                pushFromFCPAction(candidate: candidate)
            }

            if canProvisionProduction {
                provisionProductionFolderAction(candidate: result.fcpMp4Candidate)
            }

            if canRefineDescription {
                refineDescriptionAction()
            }

            if isTranscriptRow, let src = result.mp4.path {
                transcribeAction(src: src, alreadyHas: check.status == .ok)
            }

            if canPickFCP {
                fcpPickerAction()
            }

            if isHashRow {
                hashAction(status: check.status)
            }

            // Thumbnail-frames row composes two actions vertically:
            //   1. Capture — generate / re-capture the frame files
            //   2. Pick    — choose which frame is the canonical thumb
            // Capture must come first so the user "creates the source"
            // before they "select from it".
            if canShowCapture,
               let src = result.mp4.path,
               let prod = clip.productionFolder.flatMap({ ($0 as NSString).expandingTildeInPath }) {
                captureAction(src: src,
                              prod: prod,
                              n: max(1, appState.settings.numFramesToCapture),
                              status: result.thumbnailFrames.status)
            }

            if canShowPicker {
                ThumbnailFramePicker(
                    title: clip.title,
                    productionFolder: clip.productionFolder,
                    foundFrameNumbers: result.foundFrameNumbers,
                    currentSelection: liveThumbnailFilename(),
                    picked: $pickedFrame
                ) { newFilename in
                    pickThumbnail(newFilename)
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

    /// Promote the picked frame to be this clip's thumbnail. Copies the
    /// frame's bytes into `<Title>.png` in Production (so storefronts /
    /// existing tooling still have the canonical name), cleans up any
    /// stale `<Title>.png` mirror in FCP, and stores the frame's
    /// filename — `<Title>_frame_NN.png` — on `clip.thumbnailFilename`
    /// so the picker can remember which frame was picked across
    /// sessions and the editor can surface it.
    private func pickThumbnail(_ frameFilename: String) {
        do {
            guard var live = try DatabaseService.shared.fetchClip(id: clip.id) else {
                renameError = "Couldn't reload the clip — re-open the editor and try again."
                return
            }
            guard let prod = live.productionFolder, !prod.isEmpty else {
                renameError = "Production folder isn't set — can't promote the frame."
                return
            }
            // Read the frame number from the sheet's @State so what gets
            // saved exactly matches what's highlighted (eliminates any
            // race where the picker re-renders mid-click).
            let canonicalFrameName = String(format: "%@_frame_%02d.png", live.title, pickedFrame)
            _ = try FileAuditService.promoteFrameToThumbnail(
                productionFolder: prod,
                fcpFolder: live.fcpProjectFolder,
                title: live.title,
                frameFilename: canonicalFrameName
            )
            live.thumbnailFilename = canonicalFrameName
            try appState.updateClip(live)
            clearAllMessages()
            runAudit()
        } catch {
            renameError = "Couldn't promote frame: \(error.localizedDescription)"
        }
    }

    /// Inline refine pill on the Description (raw only) row. Streams
    /// the raw description through Ollama, writes the refined output
    /// onto `clip.descriptionRefined`, re-audits.
    private func refineDescriptionAction() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.caption).foregroundStyle(.purple)
            Text("Refine raw description via Ollama")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.purple)
            Spacer()
            Button {
                runRefine()
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
            .help("Stream the raw description through Ollama and save the proofread output to descriptionRefined.")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.purple.opacity(0.25), lineWidth: 1))
    }

    private func runRefine() {
        guard !refining else { return }
        refining = true
        refineMessage = nil
        let id = clip.id
        let template = appState.settings.refinePromptTemplate
        let model = appState.settings.ollamaModel
        let baseURL = appState.settings.ollamaBaseURL
        Task {
            do {
                guard let live = try DatabaseService.shared.fetchClip(id: id) else {
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
                if var updated = try DatabaseService.shared.fetchClip(id: id) {
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
                runAudit()
            } catch {
                refining = false
                refineMessage = "Refine failed: \(error.localizedDescription)"
                runAudit()
            }
        }
    }

    /// Inline pill on the missing-Main-MP4 row when an MP4 was found in
    /// the FCP folder. Clicking moves the FCP file into Production with
    /// the canonical `<Title>.mp4` name (creating Production if it
    /// doesn't exist), then re-audits.
    private func pushFromFCPAction(candidate: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.square")
                    .font(.caption).foregroundStyle(.green)
                Text("Push rendered MP4 from FCP")
                    .font(.caption.weight(.semibold)).foregroundStyle(.green)
                Spacer()
                Button {
                    runPushFromFCP(candidate: candidate)
                } label: {
                    Label("Push", systemImage: "arrow.right.square")
                }
                .controlSize(.small)
                .help("Move \(candidate) from the FCP folder into Production as `\(clip.title).mp4`. Production folder is created if missing; existing files are NOT overwritten.")
            }
            HStack(spacing: 6) {
                Text(candidate).font(.caption.monospaced()).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                Text("\(clip.title).mp4").font(.caption.monospaced())
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.green.opacity(0.25), lineWidth: 1))
    }

    /// "Create production folder" pill. Renders on the Production row when
    /// the folder is missing/warn, the clip has a content date + title, and
    /// the production-root setting is configured. Folder layout:
    ///   `<settings.defaultProductionBase>/<contentDate>/`
    /// When `candidate` is non-nil, the pill copies `<fcp>/<candidate>` →
    /// `<prod>/<sanitizedTitle>.<ext>` in the same call.
    private func provisionProductionFolderAction(candidate: String?) -> some View {
        let willCopy = candidate != nil
        let titleSafe = clip.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ext = (candidate.map { ($0 as NSString).pathExtension } ?? "")
        let destFilename = ext.isEmpty ? titleSafe : "\(titleSafe).\(ext)"
        // Mirror the same resolution provisionProductionFolder uses, so the
        // pill preview can never disagree with what actually gets created.
        let plannedPath = PathDefaultsService.productionPath(
            for: clip,
            settings: appState.settings
        ) ?? "(set the production root in Settings → File Locations)"
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
                    runProvisionProductionFolder(candidate: candidate)
                } label: {
                    Label(willCopy ? "Create + copy" : "Create",
                          systemImage: "folder.badge.plus")
                }
                .controlSize(.small)
                .help(willCopy
                      ? "Creates `\(plannedPath)`, sets it as the clip's production folder, and copies `\(candidate ?? "")` from FCP into it as `\(destFilename)`. Source stays in FCP — copy, not move."
                      : "Creates `\(plannedPath)` and sets it as the clip's production folder. No file copy.")
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

    private func runProvisionProductionFolder(candidate: String?) {
        do {
            guard let live = try DatabaseService.shared.fetchClip(id: clip.id) else {
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
            runAudit()
        } catch {
            renameError = "Provision failed: \(error.localizedDescription)"
        }
    }

    private func runPushFromFCP(candidate: String) {
        do {
            guard let live = try DatabaseService.shared.fetchClip(id: clip.id) else {
                renameError = "Couldn't reload the clip."
                return
            }
            guard let fcp = live.fcpProjectFolder, !fcp.isEmpty,
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
            runAudit()
        } catch {
            renameError = "Push failed: \(error.localizedDescription)"
        }
    }

    /// Inline hash-action pill on the File hashes audit row. Streams
    /// the main MP4 (and the reduced MP4 when present) through MD5 /
    /// SHA-1 / SHA-256, persists the digests + sizes onto the clip,
    /// re-audits so the row flips green.
    private func hashAction(status: FileAuditService.CheckStatus) -> some View {
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
                runHashAction()
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
            .help("Stream the main and reduced MP4 through MD5 / SHA-1 / SHA-256 and save the digests onto this clip.")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pillColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(pillColor.opacity(0.25), lineWidth: 1))
    }

    private func runHashAction() {
        guard !hashing else { return }
        hashing = true
        hashMessage = nil
        let id = clip.id
        Task {
            do {
                guard let live = try DatabaseService.shared.fetchClip(id: id),
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
                runAudit()
            } catch {
                hashing = false
                hashMessage = "Hash failed: \(error.localizedDescription)"
                runAudit()
            }
        }
    }

    /// Inline pill on the FCP-folder row when the path is missing or
    /// the volume is unreachable. Opens an NSOpenPanel for folder
    /// selection and saves the result onto the clip via `appState`.
    /// Re-audits afterwards so the row flips.
    private func fcpPickerAction() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.badge.gearshape")
                .font(.caption).foregroundStyle(.blue)
            Text("Set the FCP project folder")
                .font(.caption.weight(.semibold)).foregroundStyle(.blue)
            Spacer()
            Button {
                pickFCPFolder()
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

    private func pickFCPFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        panel.message = "Pick the folder containing this clip's `<Title>.fcpbundle`."
        if let p = clip.fcpProjectFolder?.trimmingCharacters(in: .whitespaces),
           !p.isEmpty {
            let expanded = (p as NSString).expandingTildeInPath
            panel.directoryURL = URL(fileURLWithPath: expanded)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            if var live = try DatabaseService.shared.fetchClip(id: clip.id) {
                // Save the standardized URL path so subsequent string-
                // based existence checks always match the volume's
                // canonical name (Unicode normalisation, trailing
                // slashes, "/private/tmp" → "/tmp", etc.).
                live.fcpProjectFolder = url.standardizedFileURL.path
                try appState.updateClip(live)
                clearAllMessages()
                runAudit()
            }
        } catch {
            renameError = "Couldn't save FCP folder: \(error.localizedDescription)"
        }
    }

    /// Big "all checks passed" banner — replaces (and effectively
    /// supersedes) the row-by-row signal when nothing's wrong.
    private func allClearBanner(in r: FileAuditService.Result) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("All checks passed")
                    .font(.title3.weight(.semibold))
                Text("\(r.allChecks.count) of \(r.allChecks.count) clean — files, thumbnail frames, description, and transcript are all in place.")
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

    /// Inline capture pill, rendered on the thumbnail-frames row above
    /// the picker. Color tracks the row status: red when no frames
    /// exist (true error), orange when partial, secondary/muted when
    /// the row is already clean (re-capture stays available without
    /// looking like an error state).
    private func captureAction(src: String, prod: String, n: Int, status: FileAuditService.CheckStatus) -> some View {
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
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle")
                    .font(.caption).foregroundStyle(pillColor)
                Text(label)
                    .font(.caption.weight(.semibold)).foregroundStyle(pillColor)
                Spacer()
                Button {
                    runCapture(sourcePath: src, productionFolder: prod, title: clip.title, n: n)
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
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pillColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(pillColor.opacity(0.25), lineWidth: 1))
    }

    /// Inline transcript-action pill — lives on the Video transcription
    /// audit row whether the transcript already exists or not. Becomes
    /// "Re-generate" once a transcript is on file so the button is
    /// always available without a separate pill at the bottom.
    private func transcribeAction(src: String, alreadyHas: Bool) -> some View {
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
                runTranscribe(sourcePath: src)
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

    /// Inline pill on the missing-reduced row that runs the AVFoundation
    /// re-encode. Disabled while a reduce is already in flight; surfaces the
    /// outcome (success or error) via `reduceMessage` in the footer.
    private func reduceAction(src: String, dst: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(.indigo)
                Text("Generate a smaller version")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.indigo)
                Spacer()
                Button {
                    runReduce(sourcePath: src, outputPath: dst)
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
                .help("Re-encode the main MP4 down to a `\((dst as NSString).lastPathComponent)` companion using HEVC / H.264 presets")
            }
            Text("Threshold: \(ByteCountFormatter.string(fromByteCount: Int64(appState.settings.largeFileThresholdMB) * 1024 * 1024, countStyle: .file)) — re-encode is iterative; we step down quality tiers until the output is under threshold.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.indigo.opacity(0.25), lineWidth: 1))
    }

    /// Inline "fix it" pill shown for any check that has a suggested rename.
    /// Single click renames the file; the audit re-runs so the row flips to
    /// `OK` immediately on success.
    private func renameSuggestion(_ s: FileAuditService.SuggestedRename) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.rays")
                    .font(.caption)
                    .foregroundStyle(.purple)
                Text("Rename to fix")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.purple)
                Spacer()
                Button {
                    applyRename(s)
                } label: {
                    Label("Rename", systemImage: "arrow.triangle.2.circlepath")
                }
                .controlSize(.small)
                .help("\(s.currentFilename) → \(s.targetFilename)")
            }
            HStack(spacing: 6) {
                Text(s.currentFilename)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                Text(s.targetFilename)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
            }
            if !s.alternatives.isEmpty {
                Text("Other candidates: \(s.alternatives.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.purple.opacity(0.25), lineWidth: 1))
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 6) {
            if let renameError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(renameError).font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") { self.renameError = nil }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let reduceMessage {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill").foregroundStyle(.indigo)
                    Text(reduceMessage).font(.caption).foregroundStyle(.indigo)
                    Spacer()
                    Button("Dismiss") { self.reduceMessage = nil }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let transcribeMessage {
                HStack(spacing: 6) {
                    Image(systemName: "waveform").foregroundStyle(.teal)
                    Text(transcribeMessage).font(.caption).foregroundStyle(.teal)
                    Spacer()
                    Button("Dismiss") { self.transcribeMessage = nil }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let captureMessage {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle").foregroundStyle(.pink)
                    Text(captureMessage).font(.caption).foregroundStyle(.pink)
                    Spacer()
                    Button("Dismiss") { self.captureMessage = nil }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let hashMessage {
                HStack(spacing: 6) {
                    Image(systemName: "function").foregroundStyle(.indigo)
                    Text(hashMessage).font(.caption).foregroundStyle(.indigo)
                    Spacer()
                    Button("Dismiss") { self.hashMessage = nil }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let refineMessage {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars").foregroundStyle(.purple)
                    Text(refineMessage).font(.caption).foregroundStyle(.purple)
                    Spacer()
                    Button("Dismiss") { self.refineMessage = nil }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text("Last audited \(stamp(lastRunAt))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                Spacer()
                if let r = result, !r.renameSuggestions.isEmpty {
                    Button {
                        applyAllRenames(r.renameSuggestions)
                    } label: {
                        Label("Fix all (\(r.renameSuggestions.count))", systemImage: "wand.and.rays")
                    }
                    .help("Apply every suggested rename, then re-audit")
                }
                if let r = result, r.hasNewDetections(against: clip) {
                    Button {
                        onApplyDetections(r)
                        dismiss()
                    } label: {
                        Label("Apply detected filenames", systemImage: "square.and.arrow.down")
                    }
                    .help("Save the detected file names back into the clip's filename columns")
                }
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
    }

    // MARK: - Actions

    private func runAudit() {
        // Read the LIVE clip from the DB so any post-action updates
        // (transcript, thumbnailFilename, etc.) are reflected in the
        // audit immediately. Falls back to the snapshot if the row was
        // somehow deleted out from under us.
        let live = (try? DatabaseService.shared.fetchClip(id: clip.id)) ?? clip
        let r = FileAuditService.audit(clip: live, settings: appState.settings)
        result = r
        lastRunAt = Date()
        // One-shot seed: if we haven't yet, seed pickedFrame from the
        // stored thumbnailFilename (or the lowest found frame).
        if !pickedSeeded {
            if let filename = live.thumbnailFilename,
               let n = ThumbnailFramePicker.parseFrameNumber(from: filename, title: live.title),
               r.foundFrameNumbers.contains(n) {
                pickedFrame = n
            } else if let first = r.foundFrameNumbers.first {
                pickedFrame = first
            }
            pickedSeeded = true
        }
    }

    /// Read the current thumbnailFilename from the live row so the
    /// picker's "Current thumbnail file" caption reflects the latest
    /// pick (the `clip` prop is a snapshot from sheet open).
    private func liveThumbnailFilename() -> String? {
        (try? DatabaseService.shared.fetchClip(id: clip.id))?.thumbnailFilename
            ?? clip.thumbnailFilename
    }

    /// Run a single rename, then re-audit. Failures surface as an inline
    /// error pill in the footer; the rest of the audit stays visible.
    private func applyRename(_ s: FileAuditService.SuggestedRename) {
        do {
            try FileAuditService.applyRename(s)
            clearAllMessages()
            runAudit()
        } catch {
            renameError = "Rename failed: \(error.localizedDescription)"
        }
    }

    /// Walk the rename queue, stopping on the first failure so the user can
    /// see exactly which rename couldn't be applied. Re-audits at the end so
    /// any partial successes show up.
    private func applyAllRenames(_ suggestions: [FileAuditService.SuggestedRename]) {
        for s in suggestions {
            do {
                try FileAuditService.applyRename(s)
            } catch {
                renameError = "Rename failed for \(s.currentFilename): \(error.localizedDescription)"
                runAudit()
                return
            }
        }
        clearAllMessages()
        runAudit()
    }

    /// Kick off the re-encode in a Task so the sheet keeps animating its
    /// spinner. On success every banner is cleared and the audit is re-
    /// run; on failure the reduce banner shows the reason and other
    /// banners stay so prior errors aren't lost.
    private func runReduce(sourcePath: String, outputPath: String) {
        guard !reducing else { return }
        reducing = true
        reduceMessage = nil
        let threshold = Int64(appState.settings.largeFileThresholdMB) * 1024 * 1024

        Task {
            do {
                _ = try await ClipReduceService.reduce(
                    sourcePath: sourcePath,
                    outputPath: outputPath,
                    thresholdBytes: threshold
                )
                reducing = false
                clearAllMessages()
                runAudit()
            } catch {
                reducing = false
                reduceMessage = "Reduce failed: \(error.localizedDescription)"
                runAudit()
            }
        }
    }

    /// Generate-transcript pill for the single-clip flow. Same UX as the
    /// workflow's pill — only shown when the main MP4 is on disk and the
    /// sibling transcribe.py is available. Persists the result via
    /// `appState.updateClip` so the editor and the live audit see it.
    @ViewBuilder
    private func transcriptPill(in result: FileAuditService.Result) -> some View {
        let mp4Status = result.mp4.status
        let mp4Available = mp4Status == .ok || mp4Status == .warn
        let scriptAvailable = TranscriptionService.locateScript() != nil
        if mp4Available, let src = result.mp4.path {
            let live = (try? DatabaseService.shared.fetchClip(id: clip.id)) ?? clip
            let alreadyHas = !live.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform").font(.caption).foregroundStyle(.teal)
                    Text(alreadyHas ? "Transcript already on file" : "Generate a whisper transcript")
                        .font(.caption.weight(.semibold)).foregroundStyle(.teal)
                    Spacer()
                    Button {
                        runTranscribe(sourcePath: src)
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
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.teal.opacity(0.25), lineWidth: 1))
        }
    }

    /// Capture-thumbnails pill — visible when the MP4 is on disk and the
    /// production folder exists. The pill takes its colour from the
    /// thumbnail-frames audit row: red when no frames exist yet (error),
    /// orange when partial, and a muted secondary tone when all frames
    /// are already in place (re-capture is still available but it's not
    /// an error state).
    @ViewBuilder
    private func capturePill(in result: FileAuditService.Result) -> some View {
        let mp4Status = result.mp4.status
        let mp4Available = mp4Status == .ok || mp4Status == .warn
        let prodReady = result.production.status == .ok
        let n = max(1, appState.settings.numFramesToCapture)
        if mp4Available, prodReady, let src = result.mp4.path,
           let prod = clip.productionFolder.flatMap({ ($0 as NSString).expandingTildeInPath }) {
            let pillColor = capturePillColor(for: result.thumbnailFrames.status)
            let label = capturePillLabel(for: result.thumbnailFrames.status, n: n)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.caption).foregroundStyle(pillColor)
                    Text(label)
                        .font(.caption.weight(.semibold)).foregroundStyle(pillColor)
                    Spacer()
                    Button {
                        runCapture(sourcePath: src, productionFolder: prod, title: clip.title, n: n)
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

    private func runTranscribe(sourcePath: String) {
        guard !transcribing else { return }
        transcribing = true
        transcribeMessage = nil
        Task {
            do {
                let outcome = try await TranscriptionService.transcribe(sourcePath: sourcePath)
                if var live = try DatabaseService.shared.fetchClip(id: clip.id) {
                    live.transcript = outcome.transcript
                    try appState.updateClip(live)
                }
                transcribing = false
                clearAllMessages()
                runAudit()
            } catch {
                transcribing = false
                transcribeMessage = "Transcribe failed: \(error.localizedDescription)"
                runAudit()
            }
        }
    }

    private func runCapture(sourcePath: String, productionFolder: String, title: String, n: Int) {
        guard !capturing else { return }
        capturing = true
        captureMessage = nil
        Task {
            do {
                _ = try await FrameCaptureService.capture(
                    sourcePath: sourcePath,
                    productionFolder: productionFolder,
                    title: title,
                    numFrames: n
                )
                capturing = false
                clearAllMessages()
                runAudit()
            } catch {
                capturing = false
                captureMessage = "Capture failed: \(error.localizedDescription)"
                runAudit()
            }
        }
    }

    private func clearAllMessages() {
        renameError = nil
        reduceMessage = nil
        transcribeMessage = nil
        captureMessage = nil
        hashMessage = nil
        refineMessage = nil
    }

    private func prettyPreset(_ preset: String) -> String {
        switch preset {
        case "AVAssetExportPresetHEVCHighestQuality": return "HEVC (source resolution)"
        case "AVAssetExportPreset1920x1080":          return "H.264 1080p"
        case "AVAssetExportPreset1280x720":           return "H.264 720p"
        case "AVAssetExportPreset960x540":            return "H.264 540p"
        default:                                      return preset
        }
    }

    // MARK: - Style helpers

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

    private func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
