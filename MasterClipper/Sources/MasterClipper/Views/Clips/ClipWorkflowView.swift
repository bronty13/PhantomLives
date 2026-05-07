import SwiftUI
import AppKit

/// New-clip workflow. Replaces the small "New Clip" sheet with a single
/// bigger sheet that captures everything the user has at clip-creation time:
///
///   • Required identity — persona, title, content date.
///   • Optional metadata — description, ordered categories, go-live date.
///   • Source folder — NSOpenPanel-picked directory that becomes the clip's
///     `fcp_project_folder`. Enumerates every `.mov` file inside, shows the
///     creation date with microsecond precision, flags any file whose current
///     filename doesn't match its 1-based chronological position, and offers
///     a one-click "Fix order" rename to `1.mov / 2.mov / …` in shoot order.
///   • Copy Status to Clipboard — saves first if needed, then drops a
///     ready-to-paste status line in the user's preferred format.
struct ClipWorkflowView: View {
    @EnvironmentObject private var appState: AppState

    let onCompleted: (Clip) -> Void
    var onContinueToEditing: ((Clip) -> Void)? = nil
    let onCancel: () -> Void

    // MARK: - Required identity
    @State private var personaCode: String = ""
    @State private var title: String = ""
    @State private var contentDateActive: Bool = false
    @State private var contentDate: Date = Date()

    // MARK: - Optional metadata
    @State private var descriptionRaw: String = ""
    @State private var selectedCategoryIds: [Int64] = []
    @State private var goLiveActive: Bool = false
    @State private var goLiveDate: Date = Date()
    @State private var notesDraft: String = ""

    // MARK: - Source folder
    @State private var folderPath: String = ""
    @State private var folderItems: [VideoFolderService.Item] = []
    @State private var folderError: String?
    @State private var fixOrderMessage: String?

    // MARK: - Save / status state
    @State private var savedClipId: String? = nil
    @State private var error: String?
    @State private var copiedFlash: Bool = false
    @State private var lastSavedAt: Date?

    // MARK: - Segment capture state
    @State private var isHashing: Bool = false
    @State private var hashCurrent: Int = 0
    @State private var hashTotal: Int = 0
    @State private var hashFilename: String = ""
    @State private var lastCaptureSummary: String?
    @State private var captureFailures: [ClipSegmentService.CaptureFailure] = []

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    sectionIdentity
                    sectionMetadata
                    sectionFolder
                }
                .padding(20)
            }
            Divider()
            actionBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(minWidth: 760, minHeight: 720)
        .onAppear {
            if personaCode.isEmpty {
                personaCode = appState.settings.defaultPersonaCode
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Clip Workflow")
                    .font(.title2.weight(.semibold))
                Text("Capture identity, metadata, and the source folder in one pass.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let id = savedClipId {
                ClipIDLabel(id: id, style: .body)
            }
        }
    }

    // MARK: - Required identity section

    private var sectionIdentity: some View {
        section("Identity", systemImage: "person.text.rectangle") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Persona") {
                    Picker("", selection: $personaCode) {
                        ForEach(appState.personas) { p in
                            Text("\(p.code) — \(p.displayName)").tag(p.code)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260, alignment: .leading)
                }

                LabeledContent("Title") {
                    TextField("Title", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Content date") {
                    HStack(spacing: 10) {
                        Toggle("", isOn: $contentDateActive)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                        if contentDateActive {
                            DatePicker("", selection: $contentDate, displayedComponents: [.date])
                                .labelsHidden()
                        } else {
                            Button("Use today (\(today))") {
                                contentDate = Date()
                                contentDateActive = true
                            }
                            .buttonStyle(.borderless)
                        }
                        Spacer()
                    }
                }

                Text("Clip ID is generated as YYYY-MM-DD-##### keyed off the content date.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if !missingRequiredFields.isEmpty {
                    Label(
                        "Required to save: \(missingRequiredFields.joined(separator: ", "))",
                        systemImage: "exclamationmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    private var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    // MARK: - Optional metadata section

    private var sectionMetadata: some View {
        section("Metadata (optional)", systemImage: "doc.text") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description").font(.callout.weight(.medium))
                    TextEditor(text: $descriptionRaw)
                        .font(.body)
                        .frame(minHeight: 80, maxHeight: 200)
                        .padding(4)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Categories").font(.callout.weight(.medium))
                    CategoryChipPicker(selectedIds: $selectedCategoryIds)
                }

                LabeledContent("Go-live date") {
                    HStack(spacing: 10) {
                        Toggle("", isOn: $goLiveActive)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                        if goLiveActive {
                            DatePicker("", selection: $goLiveDate, displayedComponents: [.date])
                                .labelsHidden()
                        } else {
                            Text("Not set")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Notes").font(.callout.weight(.medium))
                        Spacer()
                        Text("Saved as `[New clip YYYY-MM-DD] <text>` in clip notes")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    TextEditor(text: $notesDraft)
                        .font(.body)
                        .frame(minHeight: 60, maxHeight: 140)
                        .padding(4)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                }
            }
        }
    }

    // MARK: - Source folder section

    private var sectionFolder: some View {
        section("Source folder (FCP path)", systemImage: "folder") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Path…", text: $folderPath)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { reloadFolderItems() }
                    Button("Choose…", action: chooseFolder)
                    Button {
                        reloadFolderItems()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(folderPath.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if let err = folderError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }

                if !folderItems.isEmpty {
                    folderTable
                    folderActionStrip
                } else if !folderPath.trimmingCharacters(in: .whitespaces).isEmpty
                       && folderError == nil {
                    Text("No .mov files found in this folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var folderTable: some View {
        Table(folderItems) {
            TableColumn("Pos") { item in
                Text("\(item.expectedPosition)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(item.isOutOfOrder ? .orange : .secondary)
            }
            .width(40)

            TableColumn("Current name") { item in
                HStack(spacing: 6) {
                    Text(item.currentName)
                        .font(.callout.monospaced())
                        .foregroundStyle(item.isOutOfOrder ? .orange : .primary)
                    if item.isOutOfOrder {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(item.expectedName)
                            .font(.callout.monospaced())
                            .foregroundStyle(.green)
                    }
                }
            }
            .width(min: 180, ideal: 220)

            TableColumn("Creation date") { item in
                Text(item.creationDateString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .help("Microsecond-precision creation timestamp from the macOS filesystem")
            }
            .width(min: 240, ideal: 280)

            TableColumn("Status") { item in
                if item.isOutOfOrder {
                    Label("Out of order", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                } else {
                    Label("OK", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
            .width(min: 110, ideal: 130)
        }
        .frame(minHeight: 180, idealHeight: 220, maxHeight: 320)
    }

    private var folderActionStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                let outOfOrder = folderItems.filter(\.isOutOfOrder).count
                if outOfOrder > 0 {
                    Label("\(outOfOrder) of \(folderItems.count) out of order", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                } else {
                    Label("All \(folderItems.count) files are in chronological order", systemImage: "checkmark.seal")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                Spacer()
                if let msg = fixOrderMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    fixOrder()
                } label: {
                    Label("Fix order (rename to N.mov)", systemImage: "arrow.up.arrow.down.square")
                }
                .disabled(outOfOrder == 0)

                Button {
                    captureSegmentsButtonTapped()
                } label: {
                    Label("Capture file metadata", systemImage: "checkmark.shield")
                }
                .disabled(!canSave() || isHashing || folderItems.isEmpty)
                .help("Hashes every .mov (MD5 / SHA-1 / SHA-256) and stores the result as clip_segments rows for this clip. Save & Close runs this automatically.")
            }
            if let summary = lastCaptureSummary {
                Label(summary, systemImage: "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(captureFailures.isEmpty ? .green : .orange)
            }
            ForEach(Array(captureFailures.enumerated()), id: \.offset) { _, failure in
                Label("\(failure.filename): \(failure.message)", systemImage: "xmark.octagon")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            if isHashing {
                ProgressView()
                    .controlSize(.small)
                Text(hashTotal > 0
                     ? "Hashing \(hashCurrent) of \(hashTotal) — \(hashFilename)"
                     : "Hashing…")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .lineLimit(2)
            } else if !canSave() {
                Label("Required: \(missingRequiredFields.joined(separator: ", "))",
                      systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else if let saved = lastSavedAt {
                Label("Saved \(formatTime(saved))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
            Spacer()
            Button(savedClipId == nil ? "Cancel" : "Close") {
                if savedClipId == nil { onCancel() } else { closeWithSavedClip() }
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isHashing)

            Button {
                saveAndCopyStatus()
            } label: {
                Label(copiedFlash ? "Copied" : "Copy Status to Clipboard",
                      systemImage: copiedFlash ? "checkmark.circle.fill" : "doc.on.clipboard")
            }
            .disabled(!canSave() || isHashing)

            if onContinueToEditing != nil {
                Button {
                    saveAndContinueToEditing()
                } label: {
                    Label("Save & Continue to Editing →", systemImage: "wand.and.stars")
                }
                .disabled(!canSave() || isHashing)
            }

            Button(savedClipId == nil ? "Save & Close" : "Done") {
                saveAndClose()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canSave() || isHashing)
        }
    }

    /// True when the three required fields are all set: persona, title, and
    /// content date. Surfaced via the action-bar buttons' `.disabled` and the
    /// inline missing-fields hint under the Identity section.
    private func canSave() -> Bool {
        missingRequiredFields.isEmpty
    }

    /// List of human-readable missing-field labels — empty when the form is
    /// ready to save.
    private var missingRequiredFields: [String] {
        var missing: [String] = []
        if personaCode.trimmingCharacters(in: .whitespaces).isEmpty {
            missing.append("Persona")
        }
        if title.trimmingCharacters(in: .whitespaces).isEmpty {
            missing.append("Title")
        }
        if !contentDateActive {
            missing.append("Content date")
        }
        return missing
    }

    // MARK: - Folder ops

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = "Select the folder containing the .mov source files"
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.standardizedFileURL.path
            reloadFolderItems()
        }
    }

    private func reloadFolderItems() {
        let trimmed = folderPath.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            folderItems = []
            folderError = nil
            return
        }
        let url = URL(fileURLWithPath: trimmed)
        do {
            folderItems = try VideoFolderService.enumerate(folder: url)
            folderError = nil
            fixOrderMessage = nil
        } catch {
            folderItems = []
            folderError = error.localizedDescription
        }
    }

    private func fixOrder() {
        let trimmed = folderPath.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let url = URL(fileURLWithPath: trimmed)
        do {
            let steps = try VideoFolderService.fixOrder(folder: url)
            fixOrderMessage = "Renamed \(steps.count) file\(steps.count == 1 ? "" : "s")."
            reloadFolderItems()
        } catch {
            folderError = error.localizedDescription
        }
    }

    // MARK: - Save

    /// Persists the form state to the database. Pre-save creates a fresh clip;
    /// post-save updates the existing one and re-syncs categories. Returns the
    /// saved Clip on success.
    @discardableResult
    private func performSave() throws -> Clip {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let folderTrim   = folderPath.trimmingCharacters(in: .whitespaces)
        let goLiveStr    = goLiveActive ? DatabaseService.isoDate(goLiveDate) : nil

        // Phase 1: ensure a clip row exists.
        let baseClip: Clip
        if let id = savedClipId, let existing = try DatabaseService.shared.fetchClip(id: id) {
            baseClip = existing
        } else {
            baseClip = try appState.createClip(
                personaCode: personaCode,
                title: trimmedTitle,
                contentDate: contentDateActive ? contentDate : nil
            )
            savedClipId = baseClip.id
        }

        // Phase 2: overlay the workflow's optional fields and re-save.
        var updated = baseClip
        updated.title              = trimmedTitle
        updated.personaCode        = personaCode
        updated.descriptionRaw     = descriptionRaw
        updated.goLiveDate         = goLiveStr
        updated.fcpProjectFolder   = folderTrim.isEmpty ? nil : folderTrim

        // Notes appended once per save when the textarea is non-empty. Marker
        // matches the [Posted ...] / [Refined ...] / [Renamed ...] convention
        // already used elsewhere so the editor's Notes textarea reads as a
        // single timeline of context (creation → editing → posting).
        let notesTrim = notesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notesTrim.isEmpty {
            let marker = "[New clip \(DatabaseService.isoDate(Date()))] \(notesTrim)"
            let existing = updated.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if existing.contains(marker) == false {
                updated.notes = existing.isEmpty ? marker : updated.notes + "\n" + marker
            }
            // Clear the in-memory draft so a subsequent Save doesn't append a
            // duplicate. Saved + reflected in clip.notes is the source of
            // truth from this point forward.
            notesDraft = ""
        }

        try appState.updateClip(updated)

        // Phase 3: categories (positions persisted in clip_categories.position).
        try DatabaseService.shared.setCategories(
            forClip: updated.id,
            categoryIds: selectedCategoryIds
        )

        // Re-pull so we capture any side-effects (status recompute, notes
        // markers from updateClip) before handing back.
        let refreshed = try DatabaseService.shared.fetchClip(id: updated.id) ?? updated
        appState.reloadClips()
        lastSavedAt = Date()
        return refreshed
    }

    private func saveAndClose() {
        Task { await runSaveFlow(thenClose: true, copyStatusAfter: false, continueToEditing: false) }
    }

    private func saveAndCopyStatus() {
        Task { await runSaveFlow(thenClose: false, copyStatusAfter: true, continueToEditing: false) }
    }

    private func saveAndContinueToEditing() {
        Task { await runSaveFlow(thenClose: false, copyStatusAfter: false, continueToEditing: true) }
    }

    /// Save → segment-capture → optional copy/close/handoff. All side effects
    /// pass through this single async path so the hashing progress UI is
    /// consistent regardless of which button kicked it off.
    private func runSaveFlow(thenClose: Bool, copyStatusAfter: Bool, continueToEditing: Bool) async {
        do {
            let clip = try performSave()
            error = nil

            // Capture segments only when a folder is set — otherwise there's
            // nothing to hash. Failures are surfaced inline; partial success
            // (some files unreadable) is recorded as best-effort.
            let folderTrim = folderPath.trimmingCharacters(in: .whitespaces)
            if !folderTrim.isEmpty {
                await captureSegments(folder: URL(fileURLWithPath: folderTrim),
                                      clipId: clip.id)
            }

            if copyStatusAfter {
                let text = composeStatus(for: clip)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copiedFlash = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    copiedFlash = false
                }
            }

            if continueToEditing, let handoff = onContinueToEditing {
                handoff(clip)
            } else if thenClose {
                onCompleted(clip)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Hash every `.mov` in `folder`, persist as `clip_segments` rows, and
    /// drive the inline progress display. Errors don't propagate — any
    /// per-file failures are captured and shown in a summary, but the save
    /// still completes (the clip row is already in the DB by this point).
    private func captureSegments(folder: URL, clipId: String) async {
        isHashing = true
        defer { isHashing = false }
        hashCurrent = 0
        hashTotal = 0
        hashFilename = ""
        do {
            let result = try await ClipSegmentService.captureAndPersist(
                folder: folder,
                clipId: clipId
            ) { current, total, filename in
                hashCurrent = current
                hashTotal = total
                hashFilename = filename
            }
            captureFailures = result.failures
            let ok = result.segments.count - result.failures.count
            if result.failures.isEmpty {
                lastCaptureSummary = "Captured metadata for \(result.segments.count) file\(result.segments.count == 1 ? "" : "s")."
            } else {
                lastCaptureSummary = "Captured \(ok) of \(result.segments.count) — \(result.failures.count) failed (saved as metadata-only)."
            }
        } catch {
            self.error = "Segment capture failed: \(error.localizedDescription)"
        }
    }

    private func captureSegmentsButtonTapped() {
        let folderTrim = folderPath.trimmingCharacters(in: .whitespaces)
        guard !folderTrim.isEmpty else { return }
        Task {
            do {
                let clip = try performSave()
                error = nil
                await captureSegments(folder: URL(fileURLWithPath: folderTrim),
                                      clipId: clip.id)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func closeWithSavedClip() {
        if let id = savedClipId,
           let clip = try? DatabaseService.shared.fetchClip(id: id) {
            onCompleted(clip)
        } else {
            onCancel()
        }
    }

    // MARK: - Status format

    /// Builds the clipboard payload in the format the user requested:
    ///
    ///     <id> - <title> [<persona>]
    ///     Description: <desc or "Blank">
    ///     Categories: <list or "None Defined">
    ///     Go-live date: Not set        ← only when missing
    ///
    /// The Go-live row is present *only* when the clip's go-live date is
    /// missing — when set it's intentionally omitted to match the spec.
    private func composeStatus(for clip: Clip) -> String {
        let titleText = clip.title.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Untitled"
            : clip.title
        let header = "\(clip.id) - \(titleText) [\(clip.personaCode)]"

        let descTrim = clip.descriptionRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let descLine = "Description: \(descTrim.isEmpty ? "Blank" : descTrim)"

        let categoryNames = selectedCategoryIds.compactMap { id in
            appState.categories.first(where: { $0.id == id })?.name
        }
        let catList = categoryNames.isEmpty
            ? "None Defined"
            : categoryNames.joined(separator: ", ")
        let catLine = "Categories: \(catList)"

        var lines = [header, descLine, catLine]
        if (clip.goLiveDate ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("Go-live date: Not set")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .medium
        f.dateStyle = .none
        return f.string(from: date)
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
