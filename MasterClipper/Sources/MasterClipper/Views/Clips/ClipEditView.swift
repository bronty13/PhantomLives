import SwiftUI

struct ClipEditView: View {
    @EnvironmentObject private var appState: AppState
    let clip: Clip

    @State private var draft: Clip
    @State private var selectedCategoryIds: Set<Int64> = []
    @State private var initialCategoryIds: Set<Int64> = []
    @State private var saveError: String?
    @State private var lastSavedAt: Date?
    @State private var refining: Bool = false
    @State private var refineError: String?
    @State private var showingDeleteConfirm: Bool = false

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
                            statusBadge
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
                        HStack {
                            Text("FCP project folder").frame(width: 150, alignment: .leading)
                            TextField("Path…", text: bindingOptional(\.fcpProjectFolder))
                                .textFieldStyle(.roundedBorder)
                            Button("Choose…") { pickFolder(\.fcpProjectFolder) }
                        }
                        HStack {
                            Text("Production folder").frame(width: 150, alignment: .leading)
                            TextField("Path…", text: bindingOptional(\.productionFolder))
                                .textFieldStyle(.roundedBorder)
                            Button("Choose…") { pickFolder(\.productionFolder) }
                        }
                        HStack {
                            Text("Length").frame(width: 150, alignment: .leading)
                            LengthField(lengthSeconds: $draft.lengthSeconds)
                            Spacer()
                        }
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

                    Section("Notes") {
                        TextEditor(text: $draft.notes)
                            .frame(minHeight: 80)
                            .border(.separator)
                            .help("Searchable notes — title-rename markers and refine timestamps land here automatically.")
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
        .onAppear(perform: loadCategories)
        .onChange(of: clip.id) { _, _ in
            // Different clip selected — flush pending changes on the OLD draft
            // before swapping in the new one. (The .id(...) modifier in
            // ClipDetailView usually re-creates the view, but if SwiftUI
            // updates in-place this guard keeps autosave consistent.)
            autoSaveIfChanged()
            draft = clip
            loadCategories()
        }
        // Catch-all: any time this view leaves the hierarchy — different clip,
        // different sidebar section, window close — flush pending edits.
        .onDisappear { autoSaveIfChanged() }
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
                Text(draft.title.isEmpty ? "Untitled clip" : draft.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(draft.title.isEmpty ? "Untitled clip" : draft.title)

                HStack(spacing: 8) {
                    Text(draft.id)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("·").foregroundStyle(.tertiary)
                    statusBadge
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
            categoryIds: Array(selectedCategoryIds),
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
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(statusColor.opacity(0.22), in: Capsule())
        .foregroundStyle(statusColor)
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
            selectedCategoryIds = Set(ids)
            initialCategoryIds = Set(ids)
        } catch {
            saveError = error.localizedDescription
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
                categoryIds: Array(selectedCategoryIds)
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
            try DatabaseService.shared.setCategories(forClip: draft.id, categoryIds: Array(selectedCategoryIds))
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
}
