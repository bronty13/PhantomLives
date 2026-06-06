import SwiftUI
import AppKit

/// Cross-network unified search (⌘⇧F).
///
/// Searches every persisted log file across every network and surfaces
/// the matches in one list. Powered by `LogStore.search(query:
/// caseSensitive:limit:)` which scans both named-index entries and
/// orphan slug files, so freshly-restored backups still surface hits
/// even before the index gets backfilled.
///
/// Three filter affordances:
///   • Search field (.searchable-style; ⌘F focuses it).
///   • Case-sensitive toggle.
///   • Network filter chips along the top — pick a subset to narrow.
///
/// Click a result row to jump: the route picks the right
/// `IRCConnection` by network-slug match, then sets its
/// `selectedBufferID` to the buffer named in the hit. If the buffer
/// isn't currently open (channel closed / query not active), we
/// route through the existing slash-command dispatcher so the
/// connection's auto-create path materialises a fresh buffer for the
/// match.
struct UnifiedSearchView: View {
    @EnvironmentObject var model: ChatModel
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var caseSensitive: Bool = false
    @State private var hits: [LogStore.SearchHit] = []
    @State private var searching: Bool = false
    @State private var hitLimitReached: Bool = false
    @State private var selectedNetworkSlugs: Set<String> = []
    /// Debounces query keystrokes — searching is a full disk walk + AES
    /// decrypt + substring scan, so we don't want to redo it on every
    /// character. 350 ms is the trailing window.
    @State private var searchTask: Task<Void, Never>? = nil

    private static let resultLimit = 500
    private static let snippetWindow = 80  // chars around match for the snippet preview

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filtersBar
            Divider()
            resultsBody
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            if let q = model.pendingUnifiedSearchQuery {
                query = q
                model.pendingUnifiedSearchQuery = nil
                scheduleSearch()
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search every network's logs", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .onChange(of: query) { _, _ in scheduleSearch() }
                .onSubmit { scheduleSearch() }
            if searching {
                ProgressView()
                    .controlSize(.small)
            }
            Toggle("Aa", isOn: $caseSensitive)
                .toggleStyle(.button)
                .help("Case-sensitive match")
                .onChange(of: caseSensitive) { _, _ in scheduleSearch() }
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(14)
    }

    // MARK: - Filters bar

    @ViewBuilder
    private var filtersBar: some View {
        let networks = networkOptions
        if networks.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(label: "All networks",
                         isOn: selectedNetworkSlugs.isEmpty,
                         action: { selectedNetworkSlugs.removeAll() })
                    ForEach(networks, id: \.slug) { net in
                        chip(label: net.name,
                             isOn: selectedNetworkSlugs.contains(net.slug),
                             action: { toggleNetwork(net.slug) })
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private func chip(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(isOn ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12))
                )
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Results body

    @ViewBuilder
    private var resultsBody: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView(
                "Search every network",
                systemImage: "magnifyingglass",
                description: Text("Type to scan every persisted chat log across every network. Results are clickable — jump straight to the buffer where the line landed.")
            )
        } else if filteredHits.isEmpty && !searching {
            ContentUnavailableView(
                "No matches",
                systemImage: "questionmark.folder",
                description: Text("No logged line matches “\(query)”\(selectedNetworkSlugs.isEmpty ? "" : " in the selected networks").")
            )
        } else {
            List(filteredHits) { hit in
                resultRow(hit)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        jumpTo(hit)
                    }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            if hitLimitReached {
                Text("Showing the first \(Self.resultLimit) matches. Refine your query for more.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            } else if !filteredHits.isEmpty {
                Text("\(filteredHits.count) match\(filteredHits.count == 1 ? "" : "es")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private func resultRow(_ hit: LogStore.SearchHit) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(hit.buffer)
                        .font(.system(.body, design: .monospaced))
                    Text("on")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                    Text(hit.network)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                snippetView(for: hit)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                if let ts = hit.timestamp {
                    Text(relative(ts))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button("Jump") { jumpTo(hit) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    /// Compact snippet around the match. Trims the ISO-8601 prefix and
    /// shows up to `snippetWindow` chars on either side of the needle
    /// so the user has context without dragging in noise.
    @ViewBuilder
    private func snippetView(for hit: LogStore.SearchHit) -> some View {
        let body = stripTimestampPrefix(hit.line)
        Text(body)
            .font(.caption)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .truncationMode(.tail)
    }

    // MARK: - Search execution

    private func scheduleSearch() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            hits = []
            hitLimitReached = false
            return
        }
        searching = true
        let caseFlag = caseSensitive
        let store = model.logStore
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            let result = await store.search(
                query: q, caseSensitive: caseFlag, limit: Self.resultLimit)
            if Task.isCancelled { return }
            await MainActor.run {
                hits = result
                hitLimitReached = result.count >= Self.resultLimit
                searching = false
            }
        }
    }

    private var filteredHits: [LogStore.SearchHit] {
        guard !selectedNetworkSlugs.isEmpty else { return hits }
        return hits.filter { selectedNetworkSlugs.contains($0.networkSlug) }
    }

    private func toggleNetwork(_ slug: String) {
        if selectedNetworkSlugs.contains(slug) {
            selectedNetworkSlugs.remove(slug)
        } else {
            selectedNetworkSlugs.insert(slug)
        }
    }

    private struct NetworkOption: Equatable {
        let slug: String
        let name: String
    }

    /// Unique network options derived from the hit list — slug pairs to
    /// display name. Empty when there are no hits yet.
    private var networkOptions: [NetworkOption] {
        var seen: [String: String] = [:]
        for hit in hits {
            if seen[hit.networkSlug] == nil {
                seen[hit.networkSlug] = hit.network
            }
        }
        return seen
            .map { NetworkOption(slug: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Jump-to-result

    /// Switch to the right `IRCConnection` and select the matching buffer,
    /// then close the sheet. Routing lives in `ChatModel.jumpToLogHit` so the
    /// Find-nick sheet shares the exact same behaviour.
    private func jumpTo(_ hit: LogStore.SearchHit) {
        model.jumpToLogHit(hit)
        dismiss()
    }

    // MARK: - Helpers

    private func stripTimestampPrefix(_ line: String) -> String {
        guard let sp = line.firstIndex(of: " ") else { return line }
        return String(line[line.index(after: sp)...])
    }

    private func relative(_ date: Date) -> String {
        RelativeTime.string(date)
    }
}
