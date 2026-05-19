import SwiftUI

/// Single-clip Edit Tags dialog (Kyno-parity, Image #91). Pops when
/// the user right-clicks one clip → Tags…; the multi-select case
/// keeps routing to the existing `BatchTagEditorSheet` since the
/// semantics are different (additive across N clips vs replace on 1).
///
/// Layout:
///   • Title: "Tag <filename>"
///   • "Select or Create Tag" TextField + autocomplete menu
///   • Current-tags list (Remove single / Remove All)
///   • Footer: Cancel / Save Changes (disabled until edits made)
struct SingleClipTagDialog: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let assetPath: String
    let assetFilename: String

    /// Snapshot of the tags loaded on open; used to detect "any
    /// changes?" and decide whether Save Changes is enabled.
    @State private var originalTags: Set<String> = []
    /// Current edit state — mutates as the user adds / removes.
    /// Set for fast membership checks; sorted to a list at render.
    @State private var editedTags: Set<String> = []
    @State private var draft: String = ""
    @State private var selectedTagInList: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                createOrPickRow
                tagsList
                listFooter
            }
            .padding(20)
            Divider()
            footer
        }
        .frame(width: 560, height: 460)
        .onAppear(perform: loadTags)
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Text("Tag \(assetFilename)")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    /// "Select or Create Tag" row. TextField + Menu of existing tags
    /// that aren't already on the clip — picking from the menu adds
    /// instantly; typing a new name + Return / Add creates + adds.
    private var createOrPickRow: some View {
        HStack(spacing: 6) {
            TextField("Select or Create Tag", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitDraft() }
            Menu {
                let suggestions = autocompleteSuggestions
                if suggestions.isEmpty {
                    Text("No matching tags — type to create one")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(suggestions, id: \.self) { name in
                        Button(name) {
                            editedTags.insert(name)
                            draft = ""
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
        }
    }

    /// Existing-tag suggestions for the dropdown. Filters the
    /// catalog-wide tag set by the current draft text (case-
    /// insensitive `contains`) and excludes tags already on the clip.
    private var autocompleteSuggestions: [String] {
        let allKnown = Set(appState.tagIndex.values.flatMap { $0 })
        let candidates = allKnown.subtracting(editedTags)
        let q = draft.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = q.isEmpty
            ? Array(candidates)
            : candidates.filter { $0.lowercased().contains(q) }
        return filtered.sorted().prefix(20).map { $0 }
    }

    private var tagsList: some View {
        List(selection: $selectedTagInList) {
            ForEach(editedTags.sorted(), id: \.self) { tag in
                Text(tag).tag(tag)
            }
        }
        .listStyle(.bordered)
        .frame(minHeight: 200)
    }

    private var listFooter: some View {
        HStack {
            Button("Remove") {
                guard let sel = selectedTagInList else { return }
                editedTags.remove(sel)
                selectedTagInList = nil
            }
            .disabled(selectedTagInList == nil)
            Button("Remove All") {
                editedTags.removeAll()
                selectedTagInList = nil
            }
            .disabled(editedTags.isEmpty)
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save Changes") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Behavior

    private var hasChanges: Bool { editedTags != originalTags }

    private func loadTags() {
        // Make sure the clip is the active selection so AppState's
        // addTag / removeTag helpers (which key off selectedAsset)
        // target the right row.
        appState.selectedAssetPath = assetPath
        let current = Set(appState.tagIndex[assetPath] ?? [])
        originalTags = current
        editedTags = current
    }

    private func commitDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        editedTags.insert(trimmed)
        draft = ""
    }

    private func save() {
        // Drain any unsubmitted typing so the user doesn't lose a
        // half-finished tag when they hit Save.
        commitDraft()
        let toAdd = editedTags.subtracting(originalTags)
        let toRemove = originalTags.subtracting(editedTags)
        appState.selectedAssetPath = assetPath
        for name in toAdd {
            appState.addTag(name: name)
        }
        for name in toRemove {
            appState.removeTag(name: name)
        }
        dismiss()
    }
}
