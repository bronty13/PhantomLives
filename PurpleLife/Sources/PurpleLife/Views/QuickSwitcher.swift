import SwiftUI

/// ⌘K Quick Switcher — global search across every object. Opens as its
/// own window from `PurpleLifeApp`. Phase 2 acceptance gate (FTS5 across
/// all types). Result selection sets `appState.selectedTypeId` and opens
/// the picked record in the detail sheet via the main window's binding.
struct QuickSwitcher: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var hits: [SearchService.Hit] = []
    @State private var selection: Int = 0
    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search across every object…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($queryFocused)
                    .onSubmit { commitSelection() }
                    .onKeyPress(.upArrow) {
                        if !hits.isEmpty {
                            selection = max(0, selection - 1)
                        }
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        if !hits.isEmpty {
                            selection = min(hits.count - 1, selection + 1)
                        }
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        dismiss()
                        return .handled
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                        hits = []
                        selection = 0
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)

            Divider()

            if query.isEmpty {
                emptyState
            } else if hits.isEmpty {
                noResultsState
            } else {
                resultList
            }
        }
        .frame(width: 640, height: 440)
        .onAppear {
            queryFocused = true
            // Re-index in case the user just edited the schema in another
            // window; the index is cheap to rebuild.
            SearchService.reindexAll(schema: appState.schema)
        }
        .onChange(of: query) { _, q in
            // Vault types are excluded when the Vault is locked, so a
            // search across types never reveals a hit from a private
            // type the user hasn't unveiled this session.
            let exclude = appState.vaultRevealed ? Set<String>() : appState.schema.vaultTypeIds
            hits = SearchService.search(q, excludingTypeIds: exclude)
            selection = 0
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "command")
                .font(.system(size: 32)).foregroundStyle(.tertiary)
            Text("Search across People, Books, Cameras, Photo Shoots, WoW Characters, Photos…")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "questionmark.circle")
                .font(.system(size: 32)).foregroundStyle(.tertiary)
            Text("No matches for \"\(query)\".")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                    resultRow(hit: hit, isSelected: index == selection)
                        .contentShape(Rectangle())
                        .onTapGesture { selection = index; commitSelection() }
                        .onHover { hovering in if hovering { selection = index } }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func resultRow(hit: SearchService.Hit, isSelected: Bool) -> some View {
        let type = appState.schema.type(id: hit.typeId)
        let typeColor: Color = type.flatMap { Color(hex: $0.colorHex) } ?? .accentColor
        return HStack(spacing: 12) {
            Image(systemName: type?.systemImage ?? "doc")
                .foregroundStyle(typeColor)
                .frame(width: 28, height: 28)
                .background(typeColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title.isEmpty ? "Untitled" : hit.title)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(type?.name ?? hit.typeId)
                        .font(.caption2).foregroundStyle(.tertiary)
                    if !hit.body.isEmpty {
                        Text("·").foregroundStyle(.tertiary)
                        Text(hit.body)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if isSelected {
                Text("↩")
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.20) : Color.clear)
    }

    private func commitSelection() {
        guard selection < hits.count else { return }
        let hit = hits[selection]
        appState.selectedTypeId = hit.typeId
        appState.openRecordRequest = hit.recordId
        dismiss()
    }
}
