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
                    Form {
                    Section("Identity") {
                        LabeledContent("Clip ID") {
                            Text(draft.id).font(.body.monospaced()).textSelection(.enabled)
                        }
                        TextField("External Clip ID (legacy)", text: bindingOptional(\.externalClipId))
                            .textFieldStyle(.roundedBorder)
                        TextField("Tracking Tag", text: bindingOptional(\.trackingTag))
                            .textFieldStyle(.roundedBorder)
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
                        TextField("Keywords (comma-separated)", text: $draft.keywords)
                            .textFieldStyle(.roundedBorder)
                        TextField("Performers", text: $draft.performers)
                            .textFieldStyle(.roundedBorder)
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
                        HStack {
                            Text("Content date").frame(width: 90, alignment: .leading)
                            TextField("YYYY-MM-DD", text: bindingOptional(\.contentDate))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                        }
                        HStack {
                            Text("Go-Live date").frame(width: 90, alignment: .leading)
                            TextField("YYYY-MM-DD", text: bindingOptional(\.goLiveDate))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                        }
                        HStack {
                            Text("Price").frame(width: 90, alignment: .leading)
                            TextField("USD", text: priceBinding)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                        }
                    }

                    Section("Files") {
                        TextField("Clip filename",      text: bindingOptional(\.clipFilename)).textFieldStyle(.roundedBorder)
                        TextField("Thumbnail filename", text: bindingOptional(\.thumbnailFilename)).textFieldStyle(.roundedBorder)
                        TextField("Preview filename",   text: bindingOptional(\.previewFilename)).textFieldStyle(.roundedBorder)
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
