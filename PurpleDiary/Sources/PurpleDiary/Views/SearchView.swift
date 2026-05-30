import SwiftUI

/// Full-text-ish search across entries via `SearchService`. Results are ranked
/// (title-prefix > title-substring > body > tag/person). Selecting a result
/// jumps to it in the timeline.
struct SearchView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
            Divider()
            if results.isEmpty {
                emptyState
            } else {
                List(results) { result in
                    EntryRow(entry: result.entry,
                             tags: appState.tagsByEntry[result.entry.id] ?? [],
                             isSelected: false)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appState.selectedEntryId = result.entry.id
                            appState.selectedSection = .timeline
                        }
                }
                .listStyle(.inset)
            }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search entries…", text: $appState.searchQuery)
                .textFieldStyle(.plain)
            if !appState.searchQuery.isEmpty {
                Button { appState.searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(appState.searchQuery.isEmpty ? "Type to search your journal." : "No matches.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var results: [SearchService.Result] {
        guard !appState.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return SearchService.search(
            appState.searchQuery,
            in: appState.entries,
            tagsByEntry: appState.tagsByEntry,
            peopleByEntry: appState.peopleByEntry
        )
    }
}
