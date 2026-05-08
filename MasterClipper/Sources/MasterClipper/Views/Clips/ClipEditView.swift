import SwiftUI
import AppKit

struct ClipEditView: View {
    @EnvironmentObject private var appState: AppState
    let clip: Clip

    @State private var draft: Clip
    @State private var selectedCategoryIds: [Int64] = []
    @State private var initialCategoryIds: [Int64] = []
    @State private var saveError: String?
    @State private var lastSavedAt: Date?
    @State private var refining: Bool = false
    @State private var refineError: String?
    @State private var showingDeleteConfirm: Bool = false
    @State private var showingAuditSheet: Bool = false
    @State private var pendingStatusChange: PendingStatusChange?
    @State private var transcribing: Bool = false
    @State private var transcribeMessage: String?
    @State private var hashing: Bool = false
    @State private var hashMessage: String?

    // Per-segment file metadata captured by the new-clip workflow. Loaded
    // from `clip_segments` on appear / clip-id change. The recapture toggle
    // re-runs hashing against the clip's `fcp_project_folder` if set.
    @State private var segments: [ClipSegment] = []
    @State private var segmentsCapturing: Bool = false
    @State private var segmentsProgress: String = ""
    @State private var segmentsMessage: String?

    init(clip: Clip) {
        self.clip = clip
        _draft = State(initialValue: clip)
    }

    var body: some View {
        VStack(spacing: 0) {
            stickyHeader
                .background(
                    LinearGradient(
                        colors: [
                            personaColor.opacity(0.42),
                            personaColor.opacity(0.14),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(Divider(), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    auditBanner
                    Form {
                    Section("Identity") {
                        Picker("Persona", selection: $draft.personaCode) {
                            ForEach(appState.personas) { p in
                                Text("\(p.code) — \(p.displayName)").tag(p.code)
                            }
                        }
                        TextField("Title", text: $draft.title)
                            .textFieldStyle(.roundedBorder)
                    }

                    Section("Description (raw transcription)") {
                        TextEditor(text: $draft.descriptionRaw)
                            .frame(minHeight: 100)
                            .font(.body)
                            .border(.separator)
                    }

                    Section("Description (refined)") {
                        HStack {
                            Button {
                                refine()
                            } label: {
                                if refining {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text("Refining…")
                                    }
                                } else {
                                    Label("Refine via Ollama", systemImage: "wand.and.stars")
                                }
                            }
                            .disabled(refining || draft.descriptionRaw.trimmingCharacters(in: .whitespaces).isEmpty)
                            if let refineError {
                                Text(refineError).font(.caption).foregroundStyle(.red)
                            }
                            Spacer()
                            Text("Model: \(appState.settings.ollamaModel)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        TextEditor(text: $draft.descriptionRefined)
                            .frame(minHeight: 100)
                            .font(.body)
                            .border(.separator)
                    }

                    Section("Categorization") {
                        CategoryChipPicker(selectedIds: $selectedCategoryIds)
                    }

                    Section("Workflow status") {
                        HStack(spacing: 10) {
                            Text("Status").frame(width: 90, alignment: .leading)
                            statusMenu
                            if draft.statusOverride != nil {
                                Text("manual")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.indigo.opacity(0.18), in: Capsule())
                                    .foregroundStyle(.indigo)
                                    .help("Status is manually pinned. Clear the override to return to auto-derivation.")
                            }
                            Spacer()
                            Toggle("Archived", isOn: $draft.archived)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                        Text(stageHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Section("Editing (post-production)") {
                        folderRow(label: "FCP project folder", keyPath: \.fcpProjectFolder, isFCP: true)
                        folderRow(label: "Production folder",  keyPath: \.productionFolder, isFCP: false)
                        HStack {
                            Text("Length").frame(width: 150, alignment: .leading)
                            LengthField(lengthSeconds: $draft.lengthSeconds)
                            Spacer()
                        }
                        HStack {
                            Text("Files").frame(width: 150, alignment: .leading)
                            Button {
                                showingAuditSheet = true
                            } label: {
                                Label("Verify files", systemImage: "checkmark.shield")
                            }
                            .help("Check that the FCP/Production folders exist and the expected MP4, reduced MP4, thumbnail, and FCP bundle are in place")
                            Spacer()
                        }
                        HStack {
                            Text("Thumbnail").frame(width: 150, alignment: .leading)
                            if let thumb = draft.thumbnailFilename, !thumb.isEmpty {
                                Text(thumb)
                                    .font(.callout.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(thumb)
                                Button {
                                    revealThumbnail()
                                } label: {
                                    Label("Reveal", systemImage: "folder")
                                }
                                .buttonStyle(.borderless)
                                .help("Open the picked thumbnail file in Finder.")
                            } else {
                                Text("Not picked yet — open Verify files to choose a frame.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }

                    Section("Integrity") {
                        integritySection
                    }

                    Section("Schedule / pricing") {
                        optionalDateRow(label: "Content date", keyPath: \.contentDate)
                        optionalDateRow(label: "Go-Live date", keyPath: \.goLiveDate)
                        HStack {
                            Text("Price").frame(width: 100, alignment: .leading)
                            TextField("USD", text: priceBinding)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }
                    }

                    Section("Postings") {
                        PostingGrid(clipId: draft.id, personaCode: draft.personaCode)
                    }

                    Section("Posting status") {
                        postingExclusionRows
                    }

                    Section("Notes") {
                        TextEditor(text: $draft.notes)
                            .frame(minHeight: 80)
                            .border(.separator)
                            .help("Searchable notes — title-rename markers and refine timestamps land here automatically.")
                    }

                    Section("Video Transcription (auto-generated)") {
                        transcriptControls
                        TextEditor(text: $draft.transcript)
                            .frame(minHeight: 100)
                            .font(.callout)
                            .border(.separator)
                            .help("Whisper-generated transcript of the production MP4. Editable — your edits persist with the clip on save.")
                    }

                    Section("File segments") {
                        segmentsSection
                    }

                    Section("Audit") {
                        LabeledContent("Created")  { Text(draft.createdAt).font(.caption.monospaced()) }
                        LabeledContent("Updated")  { Text(draft.updatedAt).font(.caption.monospaced()) }
                        Toggle("Archived", isOn: $draft.archived)
                    }

                    Section {
                        ClipHistoryView(clipId: clip.id)
                    }
                }
                .formStyle(.grouped)

                    footer
                }
                .padding(20)
            }
        }
        .onAppear {
            loadCategories()
            loadSegments()
        }
        .onChange(of: clip.id) { _, _ in
            // Different clip selected — flush pending changes on the OLD draft
            // before swapping in the new one. (The .id(...) modifier in
            // ClipDetailView usually re-creates the view, but if SwiftUI
            // updates in-place this guard keeps autosave consistent.)
            autoSaveIfChanged()
            draft = clip
            loadCategories()
            loadSegments()
        }
        // Catch-all: any time this view leaves the hierarchy — different clip,
        // different sidebar section, window close — flush pending edits.
        .onDisappear { autoSaveIfChanged() }
        .alert(
            pendingStatusChange?.confirmTitle ?? "",
            isPresented: Binding(
                get: { pendingStatusChange != nil },
                set: { if !$0 { pendingStatusChange = nil } }
            ),
            presenting: pendingStatusChange
        ) { change in
            Button("Cancel", role: .cancel) {
                pendingStatusChange = nil
            }
            Button(change.confirmButton) {
                applyPendingStatusChange()
            }
        } message: { change in
            Text(change.message)
        }
        .alert("Delete this clip?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                do {
                    try appState.deleteClip(id: clip.id)
                } catch {
                    saveError = error.localizedDescription
                }
            }
        } message: {
            let titleText = clip.title.isEmpty ? clip.id : "\"\(clip.title)\""
            Text("\(titleText) and all its postings, category links, and history will be permanently deleted. This cannot be undone — restore from a backup if you change your mind.")
        }
        .sheet(isPresented: $showingAuditSheet) {
            FileAuditSheet(clip: draft) { result in
                if let f = result.detectedClipFilename, draft.clipFilename != f {
                    draft.clipFilename = f
                }
                if let f = result.detectedPreviewFilename, draft.previewFilename != f {
                    draft.previewFilename = f
                }
            }
        }
    }

    // MARK: - Sticky header

    /// Always-visible top bar. The title is large (`.title2`, never shrinks —
    /// truncates to "…" instead) and the persona badge is a chunky gradient
    /// pill with a heart icon for a cutesy feel.
    private var stickyHeader: some View {
        HStack(spacing: 14) {
            // Cutesy persona badge — heart over code, gradient fill, soft shadow
            VStack(spacing: 1) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                Text(draft.personaCode)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [personaColor, personaColor.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: personaColor.opacity(0.45), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 3) {
                // Title — large by default, never shrinks below this size.
                // Truncates with "…" if too long; full text in tooltip on hover.
                HStack(spacing: 6) {
                    Text(draft.title.isEmpty ? "Untitled clip" : draft.title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(draft.title.isEmpty ? "Untitled clip" : draft.title)
                    Button {
                        copyTitle()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Copy title to clipboard")
                    .disabled(draft.title.isEmpty)
                }

                HStack(spacing: 8) {
                    ClipIDLabel(id: draft.id, style: .body)
                        .foregroundStyle(.secondary)
                    Button {
                        copyClipID()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Copy clip ID to clipboard")
                    Text("·").foregroundStyle(.tertiary)
                    statusMenu
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: - Persona color

    private var personaColor: Color {
        appState.color(forPersona: draft.personaCode)
    }

    // MARK: - Status badge / hint

    // MARK: - Audit banner

    /// Live-derived audit result for the in-progress draft + selected
    /// categories. Recomputes every render — cheap, no caching needed.
    private var currentAuditResult: ClipAuditService.Result {
        ClipAuditService.audit(
            draft,
            categoryIds: selectedCategoryIds,
            appState: appState
        )
    }

    @ViewBuilder
    private var auditBanner: some View {
        let result = currentAuditResult
        if result.issues.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Clip audit — all checks passed")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
                Spacer()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.green.opacity(0.4), lineWidth: 1))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.title3)
                    Text("Clip audit — \(result.issues.count) issue\(result.issues.count == 1 ? "" : "s") to fix")
                        .font(.headline)
                    Spacer()
                }
                ForEach(result.issues) { issue in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: issue.systemImage)
                            .foregroundStyle(.orange)
                            .frame(width: 18, alignment: .center)
                        Text(issue.label)
                            .font(.callout)
                    }
                }
                Text("Fix the items above and the banner will clear automatically.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.orange.opacity(0.55), lineWidth: 1))
        }
    }

    private var statusBadge: some View {
        let s = draft.statusEnum
        return HStack(spacing: 4) {
            Image(systemName: s.systemImage).font(.caption)
            Text(s.label).font(.caption.weight(.semibold))
            Image(systemName: "chevron.down").font(.caption2)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(statusColor.opacity(0.22), in: Capsule())
        .foregroundStyle(statusColor)
    }

    /// Status badge wrapped in a Menu so the user can manually override the
    /// auto-derived value. Picking a status enqueues a confirmation alert
    /// (`pendingStatusChange`) before the override is applied — see
    /// `applyPendingStatusChange()`.
    private var statusMenu: some View {
        Menu {
            ForEach(ClipStatus.allCases.filter { $0 != .archived }, id: \.rawValue) { s in
                Button {
                    queueStatusChange(to: s.rawValue)
                } label: {
                    Label(s.label, systemImage: s.systemImage)
                }
                .disabled(draft.statusEnum == s && draft.statusOverride != nil)
            }
            if draft.statusOverride != nil {
                Divider()
                Button {
                    queueStatusChange(to: nil)
                } label: {
                    Label("Clear manual override (return to auto)", systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            statusBadge
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Change the workflow status manually. You'll be asked to confirm.")
    }

    private var statusColor: Color {
        switch draft.statusEnum {
        case .new:        return .gray
        case .editing:    return .orange
        case .toPost:     return .blue
        case .posting:    return .purple
        case .production: return .green
        case .archived:   return .secondary
        }
    }

    private var stageHint: String {
        switch draft.statusEnum {
        case .new:
            return "Status auto-advances when post-production starts. Fill in FCP project folder, production folder, and length to move forward."
        case .editing:
            let fcp = !(draft.fcpProjectFolder ?? "").isEmpty
            let prod = !(draft.productionFolder ?? "").isEmpty
            let dur = draft.lengthSeconds != nil
            let missing = [
                fcp ? nil : "FCP project folder",
                prod ? nil : "production folder",
                dur ? nil : "length"
            ].compactMap { $0 }
            return missing.isEmpty
                ? "Editing fields complete — save to move to “To Post”."
                : "Need: \(missing.joined(separator: ", ")) to advance to “To Post”."
        case .toPost:
            return "Editing complete. Open Posting Batch to start posting; the status will auto-advance once you mark the first site posted."
        case .posting:
            return "Posting in progress. The status auto-advances to “Production” when every site in the persona's scope is marked posted."
        case .production:
            return "All sites posted — clip is in production rotation."
        case .archived:
            return "Archived. Hidden from default views."
        }
    }

    // MARK: - Folder picker

    private func pickFolder(_ keyPath: WritableKeyPath<Clip, String?>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            draft[keyPath: keyPath] = url.path
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let error = saveError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if hasUnsavedChanges() {
                Label("Unsaved — auto-saves on navigation", systemImage: "pencil.circle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else if let saved = lastSavedAt {
                Label("Saved \(formatted(saved))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
            Spacer()
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Delete clip…", systemImage: "trash")
            }
            .help("Permanently delete this clip and everything linked to it")
            Button("Discard changes") {
                draft = clip
                loadCategories()
            }
            .disabled(!hasUnsavedChanges())
            Button("Save", action: save)
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!hasUnsavedChanges())
        }
    }

    // MARK: - Helpers

    private func formatted(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.timeStyle = .medium
        fmt.dateStyle = .short
        return fmt.string(from: date)
    }

    private var priceBinding: Binding<String> {
        Binding(
            get: {
                guard let cents = draft.priceCents else { return "" }
                return String(format: "%.2f", Double(cents) / 100.0)
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    draft.priceCents = nil
                } else if let v = Double(trimmed) {
                    draft.priceCents = Int((v * 100).rounded())
                }
            }
        )
    }

    private func bindingOptional(_ keyPath: WritableKeyPath<Clip, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    /// Folder row with text field, Choose / Reveal / Set default buttons.
    /// The `isFCP` flag picks which default-path computer to use.
    @ViewBuilder
    private func folderRow(label: String, keyPath: WritableKeyPath<Clip, String?>, isFCP: Bool) -> some View {
        HStack {
            Text(label).frame(width: 150, alignment: .leading)
            TextField("Path…", text: bindingOptional(keyPath))
                .textFieldStyle(.roundedBorder)
            Button {
                if let path = isFCP
                    ? PathDefaultsService.fcpPath(for: draft, settings: appState.settings)
                    : PathDefaultsService.productionPath(for: draft, settings: appState.settings) {
                    draft[keyPath: keyPath] = path
                }
            } label: {
                Image(systemName: "wand.and.rays")
            }
            .help("Set to the configured default path (Settings → File Locations)")
            .buttonStyle(.borderless)
            Button("Choose…") { pickFolder(keyPath) }
            Button {
                PathDefaultsService.revealInFinder(draft[keyPath: keyPath])
            } label: {
                Label("Reveal", systemImage: "folder")
            }
            .disabled((draft[keyPath: keyPath] ?? "").isEmpty)
            .help("Open this folder in Finder (falls back to the deepest existing parent)")
        }
    }

    /// Optional date row: shows a `DatePicker` when the field is set, otherwise
    /// a "Set date" button. The Clear button next to the picker re-nils the
    /// field. Storage stays as ISO `YYYY-MM-DD` strings — no schema change.
    @ViewBuilder
    private func optionalDateRow(label: String, keyPath: WritableKeyPath<Clip, String?>) -> some View {
        HStack(spacing: 10) {
            Text(label).frame(width: 100, alignment: .leading)
            if let parsed = Self.parseISODate(draft[keyPath: keyPath]) {
                DatePicker(label,
                    selection: Binding(
                        get: { parsed },
                        set: { newDate in
                            draft[keyPath: keyPath] = Self.formatISODate(newDate)
                        }
                    ),
                    displayedComponents: [.date]
                )
                .labelsHidden()
                Button {
                    draft[keyPath: keyPath] = nil
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Clear \(label)")
            } else {
                Text("Not set")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Set date") {
                    draft[keyPath: keyPath] = Self.formatISODate(Date())
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Spacer()
        }
    }

    private static func parseISODate(_ s: String?) -> Date? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.date(from: s.trimmingCharacters(in: .whitespaces))
    }

    private static func formatISODate(_ d: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: d)
    }

    private func loadCategories() {
        do {
            let ids = try DatabaseService.shared.categoryIds(forClip: clip.id)
            selectedCategoryIds = ids
            initialCategoryIds = ids
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - File segments (clip_segments)

    /// Disclosure-style section that lists the captured `.mov` segments for
    /// this clip with their position, filename, ctime, size, and three
    /// hashes. Read-only here (the new-clip workflow is the system of record);
    /// a "Recapture" button re-runs hashing against the FCP folder.
    @ViewBuilder
    private var segmentsSection: some View {
        if segments.isEmpty && !segmentsCapturing {
            HStack {
                Text("No file segments captured for this clip yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if (draft.fcpProjectFolder ?? "").trimmingCharacters(in: .whitespaces).isEmpty == false {
                    Button("Capture from FCP folder", action: recaptureSegments)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if segmentsCapturing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(segmentsProgress)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                if let msg = segmentsMessage {
                    Text(msg).font(.caption2).foregroundStyle(.secondary)
                }
                segmentsTable
                HStack {
                    Text("\(segments.count) segment\(segments.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh", action: loadSegments)
                        .disabled(segmentsCapturing)
                    Button("Recapture", action: recaptureSegments)
                        .disabled(segmentsCapturing
                                  || (draft.fcpProjectFolder ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Re-hash every .mov in the FCP folder and replace the stored segment rows.")
                }
            }
        }
    }

    private var segmentsTable: some View {
        Table(segments) {
            TableColumn("#") { (s: ClipSegment) in
                Text("\(s.position)").font(.caption.monospacedDigit())
            }
            .width(30)

            TableColumn("Filename") { (s: ClipSegment) in
                Text(s.filename).font(.caption.monospaced()).textSelection(.enabled)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Created") { (s: ClipSegment) in
                Text(s.creationDate).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .width(min: 220, ideal: 260)

            TableColumn("Size") { (s: ClipSegment) in
                Text(Self.formatSize(s.sizeBytes)).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 80)

            TableColumn("MD5") { (s: ClipSegment) in
                hashCell(s.md5)
            }
            .width(min: 90, ideal: 110)

            TableColumn("SHA-1") { (s: ClipSegment) in
                hashCell(s.sha1)
            }
            .width(min: 90, ideal: 110)

            TableColumn("SHA-256") { (s: ClipSegment) in
                hashCell(s.sha256)
            }
            .width(min: 90, ideal: 110)
        }
        .frame(minHeight: 140, idealHeight: 200, maxHeight: 320)
    }

    /// Truncated hash with click-to-copy + the full digest as tooltip.
    @ViewBuilder
    private func hashCell(_ hex: String) -> some View {
        if hex.isEmpty {
            Text("—").font(.caption2).foregroundStyle(.tertiary)
        } else {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hex, forType: .string)
            } label: {
                Text(String(hex.prefix(10)) + "…")
                    .font(.caption2.monospaced())
            }
            .buttonStyle(.borderless)
            .help(hex + "\n\nClick to copy")
        }
    }

    private static func formatSize(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    private func loadSegments() {
        do {
            segments = try DatabaseService.shared.fetchSegments(forClip: clip.id)
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func recaptureSegments() {
        let trimmed = (draft.fcpProjectFolder ?? "").trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let url = URL(fileURLWithPath: trimmed)
        let clipId = clip.id
        segmentsCapturing = true
        segmentsProgress = ""
        segmentsMessage = nil
        Task {
            defer { segmentsCapturing = false }
            do {
                let result = try await ClipSegmentService.captureAndPersist(
                    folder: url,
                    clipId: clipId
                ) { current, total, filename in
                    segmentsProgress = "Hashing \(current) of \(total) — \(filename)"
                }
                segments = result.segments
                segmentsMessage = result.failures.isEmpty
                    ? "Captured metadata for \(result.segments.count) file\(result.segments.count == 1 ? "" : "s")."
                    : "Captured \(result.segments.count - result.failures.count) of \(result.segments.count) — \(result.failures.count) failed."
            } catch {
                segmentsMessage = "Capture failed: \(error.localizedDescription)"
            }
        }
    }

    /// True when either the clip fields or the category selection has been
    /// touched since the last save / load. Used by autosave to skip no-op
    /// writes (which would otherwise spam history rows on every navigation).
    private func hasUnsavedChanges() -> Bool {
        draft != clip || selectedCategoryIds != initialCategoryIds
    }

    /// Best-effort silent save. Errors are swallowed because autosave runs
    /// as the view is leaving — there's no UI to surface them on. The next
    /// explicit Save will resurface the same problem if it persists.
    private func autoSaveIfChanged() {
        guard hasUnsavedChanges() else { return }
        do {
            try appState.updateClip(draft)
            try DatabaseService.shared.setCategories(
                forClip: draft.id,
                categoryIds: selectedCategoryIds
            )
            initialCategoryIds = selectedCategoryIds
            lastSavedAt = Date()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func refine() {
        let raw = draft.descriptionRaw
        guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
            refineError = "Paste a raw description first."
            return
        }
        refining = true
        refineError = nil
        let template = appState.settings.refinePromptTemplate
        let model = appState.settings.ollamaModel
        let baseURL = appState.settings.ollamaBaseURL
        let wasEmpty = draft.descriptionRefined.trimmingCharacters(in: .whitespaces).isEmpty
        draft.descriptionRefined = ""

        Task {
            do {
                try await OllamaService.refine(
                    description: raw,
                    promptTemplate: template,
                    model: model,
                    baseURLString: baseURL,
                    onToken: { token in
                        draft.descriptionRefined += token
                    }
                )
                // Post-process: peel any matched pair of wrapping quotes the
                // model produced AND normalise whitespace into clean paragraph
                // format (single-space runs, no trailing whitespace, single
                // blank line between paragraphs). The prompt asks for this but
                // small models drift; this pass is the deterministic safety net.
                draft.descriptionRefined = OllamaService.cleanRefineOutput(draft.descriptionRefined)
                refining = false
                if wasEmpty {
                    let stamp = "[Refined \(DatabaseService.isoDate(Date()))]"
                    if !draft.notes.contains(stamp) {
                        draft.notes = draft.notes.isEmpty ? stamp : draft.notes + "\n" + stamp
                    }
                }
            } catch {
                refining = false
                refineError = error.localizedDescription
            }
        }
    }

    private func save() {
        do {
            try appState.updateClip(draft)
            try DatabaseService.shared.setCategories(forClip: draft.id, categoryIds: selectedCategoryIds)
            // Re-pull the saved row (server-side may have appended notes)
            if let refreshed = try DatabaseService.shared.fetchClip(id: draft.id) {
                draft = refreshed
            }
            initialCategoryIds = selectedCategoryIds
            saveError = nil
            lastSavedAt = Date()
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Transcript

    @ViewBuilder
    private var transcriptControls: some View {
        let mp4Path = expectedMP4Path()
        let scriptAvailable = TranscriptionService.locateScript() != nil
        let canTranscribe = mp4Path != nil && scriptAvailable && !transcribing
        HStack(spacing: 10) {
            Button {
                runTranscribe()
            } label: {
                if transcribing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Transcribing…")
                    }
                } else {
                    Label("Generate transcript", systemImage: "waveform")
                }
            }
            .disabled(!canTranscribe)
            .help(transcribeHelpText(mp4Path: mp4Path, scriptAvailable: scriptAvailable))
            if !draft.transcript.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(draft.transcript, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }
            Spacer()
            if let msg = transcribeMessage {
                Text(msg).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    /// Returns the canonical `<production>/<Title>.mp4` path that the
    /// audit + reduce pipeline already use. Nil when the production folder
    /// or title isn't filled in yet.
    private func expectedMP4Path() -> String? {
        let prod = (draft.productionFolder ?? "").trimmingCharacters(in: .whitespaces)
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prod.isEmpty, !title.isEmpty else { return nil }
        let expanded = (prod as NSString).expandingTildeInPath
        return ((expanded as NSString).appendingPathComponent(title) as NSString).appendingPathExtension("mp4")
    }

    private func transcribeHelpText(mp4Path: String?, scriptAvailable: Bool) -> String {
        if !scriptAvailable {
            return "transcribe.py not found at ~/Documents/GitHub/PhantomLives/transcribe/ — install the sibling project first."
        }
        if mp4Path == nil {
            return "Set the production folder + title first; transcription reads <production>/<Title>.mp4"
        }
        return "Run MLX whisper on the production MP4 and store the transcript here."
    }

    // MARK: - Posting exclusion

    @ViewBuilder
    private var postingExclusionRows: some View {
        Toggle("Exclude from posting", isOn: $draft.postingExcluded)
            .toggleStyle(.switch)
            .help("Excluded clips are filtered out of every per-site posting batch and the Posting Queue.")
        if draft.postingExcluded {
            HStack {
                Text("Reason").frame(width: 100, alignment: .leading)
                Picker("Reason", selection: $draft.exclusionReason) {
                    Text("(pick one)").tag("")
                    ForEach(appState.exclusionReasons.filter { !$0.archived }) { r in
                        Text(r.label).tag(r.label)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes (free text — useful for \"Other\" / \"Custom\" reasons)")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $draft.exclusionNotes)
                    .frame(minHeight: 50, maxHeight: 80)
                    .border(.separator)
            }
        }
    }

    // MARK: - Integrity (file hashes)

    @ViewBuilder
    private var integritySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("File hashes").font(.callout.weight(.semibold))
                Spacer()
                if hashing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Hashing…").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        runHash()
                    } label: {
                        Label("Recompute hashes", systemImage: "function")
                    }
                    .help("Stream both the main and reduced MP4 through MD5 / SHA-1 / SHA-256 and save the digests onto this clip.")
                }
            }

            if !draft.hashesComputedAt.isEmpty {
                Text("Last computed \(draft.hashesComputedAt)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            if let msg = hashMessage {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill").foregroundStyle(.indigo)
                    Text(msg).font(.caption).foregroundStyle(.indigo)
                    Spacer()
                    Button("Dismiss") { hashMessage = nil }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            }

            hashFileBlock(
                title: "Main MP4",
                sizeBytes: draft.mp4SizeBytes,
                md5: draft.mp4Md5, sha1: draft.mp4Sha1, sha256: draft.mp4Sha256
            )
            hashFileBlock(
                title: "Reduced MP4",
                sizeBytes: draft.reducedSizeBytes,
                md5: draft.reducedMd5, sha1: draft.reducedSha1, sha256: draft.reducedSha256
            )
        }
    }

    private func hashFileBlock(title: String, sizeBytes: Int64?, md5: String, sha1: String, sha256: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title).font(.caption.weight(.semibold))
                if let s = sizeBytes {
                    Text(ByteCountFormatter.string(fromByteCount: s, countStyle: .file))
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                } else {
                    Text("size unknown").font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
            }
            hashRow(label: "MD5",    digest: md5)
            hashRow(label: "SHA-1",  digest: sha1)
            hashRow(label: "SHA-256", digest: sha256)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func hashRow(label: String, digest: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2.weight(.medium))
                .frame(width: 64, alignment: .leading)
                .foregroundStyle(.secondary)
            if digest.isEmpty {
                Text("not yet computed")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                Text(digest)
                    .font(.caption2.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(digest)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(digest, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Copy \(label) to the clipboard.")
            }
        }
    }

    /// Hash the main MP4 (and the reduced MP4 if it exists) in one
    /// background pass, persist the digests + sizes, and refresh the
    /// editor's draft so the new values render immediately.
    private func runHash() {
        guard !hashing else { return }
        hashMessage = nil
        guard let mainPath = expectedMP4Path() else {
            hashMessage = "Set the production folder + title first."
            return
        }
        let reducedPath = expectedReducedMP4Path()

        hashing = true
        let id = clip.id
        Task {
            do {
                let main = try await HashService.hash(filePath: mainPath)
                let reduced: HashService.Hashes? = await {
                    guard let p = reducedPath, FileManager.default.fileExists(atPath: p) else { return nil }
                    return try? await HashService.hash(filePath: p)
                }()

                if var live = try DatabaseService.shared.fetchClip(id: id) {
                    live.mp4Md5         = main.md5
                    live.mp4Sha1        = main.sha1
                    live.mp4Sha256      = main.sha256
                    live.mp4SizeBytes   = main.sizeBytes
                    if let r = reduced {
                        live.reducedMd5        = r.md5
                        live.reducedSha1       = r.sha1
                        live.reducedSha256     = r.sha256
                        live.reducedSizeBytes  = r.sizeBytes
                    } else {
                        live.reducedMd5 = ""
                        live.reducedSha1 = ""
                        live.reducedSha256 = ""
                        live.reducedSizeBytes = nil
                    }
                    live.hashesComputedAt = DatabaseService.isoNow()
                    try appState.updateClip(live)
                    draft = live
                }
                let n = reduced == nil ? 1 : 2
                hashMessage = "Hashed \(n) file\(n == 1 ? "" : "s")."
                hashing = false
            } catch {
                hashMessage = "Hash failed: \(error.localizedDescription)"
                hashing = false
            }
        }
    }

    /// Mirror of `expectedMP4Path()` for the reduced companion.
    private func expectedReducedMP4Path() -> String? {
        let prod = (draft.productionFolder ?? "").trimmingCharacters(in: .whitespaces)
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prod.isEmpty, !title.isEmpty else { return nil }
        let expanded = (prod as NSString).expandingTildeInPath
        let name = title + "_reduced.mp4"
        return (expanded as NSString).appendingPathComponent(name)
    }

    private func copyTitle() {
        let value = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func copyClipID() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(draft.id, forType: .string)
    }

    // MARK: - Manual status override

    /// Pending change captured when the user picks a new status from the
    /// menu. Storing this state triggers the confirmation alert; the user
    /// then confirms / cancels in `applyPendingStatusChange()`.
    private struct PendingStatusChange: Identifiable {
        let id = UUID()
        let newOverride: String?   // nil = clear override, return to auto
        let fromLabel: String
        let toLabel: String

        var confirmTitle: String {
            newOverride == nil ? "Clear manual status override?" : "Change status manually?"
        }
        var confirmButton: String {
            newOverride == nil ? "Clear override" : "Change status"
        }
        var message: String {
            if newOverride == nil {
                return "Status will return to auto-derivation from posting state and editing fields. Currently pinned to “\(fromLabel)”."
            }
            return "Pin this clip's status to “\(toLabel)” (currently “\(fromLabel)”). The override sticks until you clear it — auto-derivation is suspended while it's set."
        }
    }

    private func queueStatusChange(to newOverrideRaw: String?) {
        let from = ClipStatus(rawValue: draft.status)?.label ?? draft.status
        let to: String
        if let raw = newOverrideRaw, let s = ClipStatus(rawValue: raw) {
            to = s.label
        } else {
            to = "auto"
        }
        // Don't prompt when the picked value matches the current override
        // exactly — nothing to confirm.
        if newOverrideRaw == draft.statusOverride { return }
        pendingStatusChange = PendingStatusChange(
            newOverride: newOverrideRaw,
            fromLabel: from,
            toLabel: to
        )
    }

    private func applyPendingStatusChange() {
        guard let change = pendingStatusChange else { return }
        defer { pendingStatusChange = nil }
        // Flush in-flight edits first so the override write doesn't race
        // against an autosave that would re-run computeStatus.
        autoSaveIfChanged()
        do {
            try appState.setClipStatusOverride(clipId: clip.id, override: change.newOverride)
            // Re-pull so the editor reflects the persisted status + notes marker.
            if let refreshed = try DatabaseService.shared.fetchClip(id: clip.id) {
                draft = refreshed
            }
            saveError = nil
            lastSavedAt = Date()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func revealThumbnail() {
        guard let thumb = draft.thumbnailFilename, !thumb.isEmpty,
              let prod = draft.productionFolder?.trimmingCharacters(in: .whitespaces),
              !prod.isEmpty else { return }
        let expanded = (prod as NSString).expandingTildeInPath
        let path = (expanded as NSString).appendingPathComponent(thumb)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: expanded)])
        }
    }

    private func runTranscribe() {
        guard !transcribing, let path = expectedMP4Path() else { return }
        transcribing = true
        transcribeMessage = nil
        Task {
            do {
                let outcome = try await TranscriptionService.transcribe(sourcePath: path)
                draft.transcript = outcome.transcript
                let secs = String(format: "%.1fs", outcome.durationSeconds)
                transcribeMessage = "Transcribed in \(secs) (\(outcome.wordCount) words)"
                transcribing = false
            } catch {
                transcribeMessage = "Transcribe failed: \(error.localizedDescription)"
                transcribing = false
            }
        }
    }
}
