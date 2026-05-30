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
    @State private var loaded = false
    @State private var saveWorkItem: DispatchWorkItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                tagRow
                MarkdownEditor(text: $body_)
            }
            .padding(20)
        }
        .onAppear(perform: loadIfNeeded)
        .onDisappear(perform: flushSave)
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
                Spacer()
                MoodStarsView(mood: $mood, starSize: 18)
            }
            TextField("Title", text: $title, prompt: Text("Title (optional)"))
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
        }
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

    // MARK: - Load / save

    private func loadIfNeeded() {
        guard !loaded else { return }
        title = entry.title
        body_ = entry.bodyMarkdown
        date = entry.dateValue
        mood = entry.mood
        selectedTagIds = Set((try? DatabaseService.shared.tagIDs(forEntry: entry.id)) ?? [])
        loaded = true
    }

    private func scheduleSave() {
        guard loaded else { return }
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { persist() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func flushSave() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        if loaded { persist() }
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
