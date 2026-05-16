import SwiftUI

/// Type-ahead picker for the cross-cutting tag vocabulary. Used by
/// `TagPillRow` on Detail and (later) by `SearchScreen`'s tag filter.
/// The picker itself doesn't render the currently-selected chips — its
/// host view shows those — it surfaces filtered suggestions matching
/// the typed query plus a "Create '\(typed)'" affordance when the typed
/// text doesn't match an existing tag.
///
/// Inputs:
/// - `selectedTagIds`: ids already attached (filtered out of suggestions)
/// - `onPick`: invoked with the chosen / newly-created tag id
struct TagChipPicker: View {
    let selectedTagIds: Set<String>
    let onPick: (String) -> Void

    @State private var query: String = ""
    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Add tag…", text: $query)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .focused($queryFocused)
                .onSubmit(commitTopChoice)
            Divider()
            suggestionList
        }
        .frame(width: 240)
        .onAppear { queryFocused = true }
    }

    // MARK: - Suggestions

    private var matches: [TagDef] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let allTags = TagService.allTags
        let available = allTags.filter { !selectedTagIds.contains($0.id) }
        guard !trimmed.isEmpty else { return available }
        let lower = trimmed.lowercased()
        return available.filter { $0.name.lowercased().contains(lower) }
    }

    /// True when the typed query is non-empty and doesn't case-
    /// insensitively match any existing tag's name — in which case the
    /// picker shows a "Create '\(query)'" row at the bottom.
    private var canCreateNew: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return TagService.tag(name: trimmed) == nil
    }

    @ViewBuilder
    private var suggestionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(matches) { tag in
                    Button {
                        onPick(tag.id)
                        query = ""
                    } label: {
                        suggestionRow(tag: tag)
                    }
                    .buttonStyle(.plain)
                }
                if canCreateNew {
                    if !matches.isEmpty { Divider() }
                    Button {
                        createAndPick()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.accentColor)
                            Text("Create \u{201C}\(query.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}")
                                .lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                if matches.isEmpty && !canCreateNew {
                    Text(TagService.allTags.isEmpty
                         ? "No tags yet. Type a name to create one."
                         : "Every tag matching that text is already attached.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                }
            }
        }
        .frame(maxHeight: 220)
    }

    private func suggestionRow(tag: TagDef) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tag.colorHex.flatMap(Color.init(hex:)) ?? .secondary)
                .frame(width: 8, height: 8)
            Text(tag.name).lineLimit(1)
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    // MARK: - Actions

    /// Submit behaviour: if the top match is non-empty, pick it.
    /// Otherwise, if the query can produce a new tag, create it.
    private func commitTopChoice() {
        if let first = matches.first {
            onPick(first.id)
            query = ""
        } else if canCreateNew {
            createAndPick()
        }
    }

    private func createAndPick() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let created = TagService.add(name: trimmed) else { return }
        onPick(created.id)
        query = ""
    }
}
