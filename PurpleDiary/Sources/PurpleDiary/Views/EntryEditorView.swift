import SwiftUI

/// The entry editor: editable date, title, mood stars, tag chips, and the
/// Markdown body. Edits are buffered in local `@State` and persisted on a
/// short debounce + on disappear, so typing stays smooth and we don't write
/// to SQLite on every keystroke.
struct EntryEditorView: View {
    @EnvironmentObject private var appState: AppState
    let entry: Entry

    @State private var title: String = ""
    @State private var body_: String = ""
    @State private var date: Date = Date()
    @State private var mood: Mood = .unset
    @State private var selectedTagIds: Set<Int64> = []
    @State private var trackerValues: [Int64: Double] = [:]
    @State private var journalId: String = Journal.defaultId
    @State private var prompt: Prompt = PromptService.prompt(for: Date())
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                tagRow
                if !appState.trackerTags.isEmpty { trackerRow }
                EntryPhotosSection(entry: entry, onInsert: insertInline)
                if body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    promptCard
                }
                MarkdownEditor(text: $body_)
            }
            .padding(20)
        }
        .onAppear(perform: loadIfNeeded)
        .onDisappear(perform: leaveEditor)
        .onChange(of: title) { _, _ in scheduleSave() }
        .onChange(of: body_) { _, _ in scheduleSave() }
        .onChange(of: date) { _, _ in scheduleSave() }
        .onChange(of: mood) { _, _ in scheduleSave() }
        .onChange(of: selectedTagIds) { _, _ in saveTags() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.field)
                journalMenu
                Spacer()
                MoodStarsView(mood: $mood, starSize: 18)
            }
            TextField("Title", text: $title, prompt: Text("Title (optional)"))
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
        }
    }

    /// Move this entry between journals. Only journals currently visible
    /// (non-hidden or unlocked) are offered.
    private var journalMenu: some View {
        Menu {
            ForEach(appState.visibleJournals) { j in
                Button {
                    moveToJournal(j.id)
                } label: {
                    Label(j.name, systemImage: j.id == journalId ? "checkmark" : j.symbol)
                }
            }
        } label: {
            Label(appState.journalsById[journalId]?.name ?? "Journal", systemImage: "book.closed")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Move this entry to another journal")
    }

    private func moveToJournal(_ id: String) {
        guard loaded, id != journalId else { return }
        journalId = id
        do { try appState.setEntryJournal(id, entryId: entry.id) }
        catch { appState.errorMessage = error.localizedDescription }
    }

    // MARK: - Writing prompt (shown only while the body is empty)

    private var promptCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(appState.effectiveAccentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Text(prompt.category)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            VStack(spacing: 6) {
                Button("Use") { usePrompt() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                Button { prompt = PromptService.next(after: prompt) } label: {
                    Image(systemName: "shuffle").font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Show another prompt")
            }
        }
        .padding(12)
        .background(appState.effectiveAccentColor.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(appState.effectiveAccentColor.opacity(0.25), lineWidth: 1))
    }

    private func usePrompt() {
        body_ = "> \(prompt.text)\n\n"
    }

    /// Insert an inline reference to an attachment at the end of the body. The
    /// user can reposition it or add a caption in Write mode; Preview renders the
    /// media in place. Works for any attachment kind (photo/video/audio/pdf/file).
    private func insertInline(_ thumb: AttachmentThumb) {
        let ref = InlineMedia.ref(attachmentId: thumb.id)
        let separator = body_.isEmpty || body_.hasSuffix("\n") ? "" : "\n\n"
        body_ += "\(separator)\(ref)\n"
    }

    // MARK: - Tags

    private var tagRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            FlowChips(tags: appState.tags, selected: $selectedTagIds)
        }
    }

    // MARK: - Trackers

    private var trackerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trackers")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                ForEach(appState.trackerTags) { tracker in
                    TrackerLogRow(
                        tracker: tracker,
                        value: tracker.rowId.flatMap { trackerValues[$0] },
                        onCommit: { newValue in commitTracker(tracker, newValue) }
                    )
                }
            }
        }
    }

    private func commitTracker(_ tracker: TrackerTag, _ value: Double?) {
        guard loaded, let rid = tracker.rowId else { return }
        if let value { trackerValues[rid] = value } else { trackerValues[rid] = nil }
        do {
            try appState.setTrackerValue(value, trackerTagId: rid, forEntry: entry.id)
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Load / save

    private func loadIfNeeded() {
        guard !loaded else { return }
        title = entry.title
        body_ = entry.bodyMarkdown
        date = entry.dateValue
        mood = entry.mood
        selectedTagIds = Set((try? DatabaseService.shared.tagIDs(forEntry: entry.id)) ?? [])
        trackerValues = (try? DatabaseService.shared.trackerValues(forEntry: entry.id)) ?? [:]
        journalId = entry.journalId
        prompt = PromptService.prompt(for: entry.dateValue)
        loaded = true
    }

    private func scheduleSave() {
        guard loaded else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            persist()
        }
    }

    /// Leaving the editor (switching entries, sections, or closing): cancel the
    /// debounce, then either discard a never-filled-in entry or persist real
    /// edits. The discard is silent — no "delete blank entry?" prompt — because
    /// a completely empty entry has nothing to lose. See `AppState.entryIsEmpty`.
    private func leaveEditor() {
        saveTask?.cancel()
        saveTask = nil
        guard loaded else { return }
        if appState.discardEntryIfEmpty(entry.id, title: title, body: body_, mood: mood) {
            return
        }
        persist()
    }

    private func persist() {
        var updated = entry
        updated.title = title
        updated.bodyMarkdown = body_
        updated.date = ISO8601DateFormatter().string(from: date)
        updated.mood = mood
        do {
            try appState.updateEntry(updated)
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func saveTags() {
        guard loaded else { return }
        do {
            try appState.setTags(Array(selectedTagIds), forEntry: entry.id)
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}

/// Wrapping row of toggleable tag chips.
struct FlowChips: View {
    let tags: [Tag]
    @Binding var selected: Set<Int64>

    var body: some View {
        if tags.isEmpty {
            Text("No tags yet — add some in the Tags section.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            // Simple wrapping layout via a LazyVGrid of adaptive columns.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6, alignment: .leading)],
                      alignment: .leading, spacing: 6) {
                ForEach(tags) { tag in
                    chip(tag)
                }
            }
        }
    }

    private func chip(_ tag: Tag) -> some View {
        let isOn = tag.rowId.map { selected.contains($0) } ?? false
        let color = Color(hex: tag.colorHex) ?? .gray
        return Button {
            guard let rid = tag.rowId else { return }
            if isOn { selected.remove(rid) } else { selected.insert(rid) }
        } label: {
            Text(tag.name)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(isOn ? 0.5 : 0.18), in: Capsule())
                .overlay(Capsule().stroke(color.opacity(isOn ? 0.8 : 0), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// One row for logging a tracker's value on an entry. The control depends on
/// the tracker's kind: a numeric field (number / duration in minutes) or a
/// three-state picker (— / No / Yes) for booleans. Empty / "—" clears the
/// logged value entirely (so an un-logged tracker stays un-logged rather than
/// being recorded as zero). Commits on Enter and on focus loss.
struct TrackerLogRow: View {
    let tracker: TrackerTag
    let value: Double?
    let onCommit: (Double?) -> Void

    @State private var text: String = ""
    @State private var boolChoice: Int = -1     // -1 = unset, 0 = no, 1 = yes
    @FocusState private var focused: Bool

    private var color: Color { Color(hex: tracker.colorHex) ?? .gray }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(tracker.name).font(.callout)
                if let v = value {
                    Text("Logged: \(tracker.kind.format(v, unit: tracker.unit))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            control
        }
        .padding(.vertical, 2)
        .onAppear(perform: sync)
        .onChange(of: value) { _, _ in sync() }
    }

    @ViewBuilder
    private var control: some View {
        switch tracker.kind {
        case .boolean:
            Picker("", selection: $boolChoice) {
                Text("—").tag(-1)
                Text("No").tag(0)
                Text("Yes").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            .onChange(of: boolChoice) { _, new in
                onCommit(new < 0 ? nil : Double(new))
            }
        default:
            HStack(spacing: 4) {
                TextField(tracker.kind == .duration ? "min" : (tracker.unit.isEmpty ? "value" : tracker.unit),
                          text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
                    .onSubmit(commitNumber)
                    .onChange(of: focused) { _, isFocused in if !isFocused { commitNumber() } }
                Text(tracker.kind == .duration ? "min" : tracker.unit)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(minWidth: 28, alignment: .leading)
            }
        }
    }

    private func sync() {
        switch tracker.kind {
        case .boolean:
            boolChoice = value.map { $0 >= 0.5 ? 1 : 0 } ?? -1
        default:
            if let v = value {
                text = v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
            } else {
                text = ""
            }
        }
    }

    private func commitNumber() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            onCommit(nil)
        } else if let d = Double(trimmed.replacingOccurrences(of: ",", with: ".")) {
            onCommit(d)
        }
    }
}
