import SwiftUI

/// Searchable, sortable channel directory. Fed by `ChannelListService` which
/// collects RPL_LIST (322/323) replies. Double-click or Join button issues a
/// /join for the selected row and closes the sheet.
struct ChannelListView: View {
    @ObservedObject var service: ChannelListService
    var onJoin: (String) -> Void
    /// filter = server-side /LIST arg; full = wipe cache and re-fetch.
    var onRefresh: (_ filter: String, _ full: Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var useRegex: Bool = false
    @State private var listFilter: String = ""   // server-side /LIST filter arg
    @State private var selection: ChannelListService.Listing.ID?
    @State private var sortOrder: [KeyPathComparator<ChannelListService.Listing>] = [
        KeyPathComparator(\.users, order: .reverse)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Table(filtered, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Channel", value: \.name) { row in
                    Text(row.name)
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 140, ideal: 200)
                TableColumn("Users", value: \.users) { row in
                    Text("\(row.users)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 60, ideal: 70, max: 90)
                TableColumn("Topic", value: \.topic) { row in
                    Text(row.topic)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.secondary)
                        .help(row.topic)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: ChannelListService.Listing.ID.self) { ids in
                if let id = ids.first {
                    Button("Join \(id)") { join(id) }
                }
            } primaryAction: { ids in
                if let id = ids.first { join(id) }
            }
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 500)
    }

    // MARK: - Header (search + filter)

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find in channel name or topic…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Toggle("Regex", isOn: $useRegex)
                    .toggleStyle(.switch)
                    .help("Treat find text as a case-insensitive regular expression")
            }
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
                TextField("Server-side /LIST filter (e.g. >5, #swift*, <100) — optional", text: $listFilter)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { onRefresh(listFilter, false) }
                Button {
                    onRefresh(listFilter, false)
                } label: {
                    if service.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(service.isLoading)
                .help("Re-issue LIST with the filter above (keeps any cached rows the server omits)")
                Button {
                    onRefresh("", true)
                } label: {
                    Label("Full refresh", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(service.isLoading)
                .help("Wipe the cached directory and re-fetch from scratch")
            }
            if let regexError {
                Text(regexError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
    }

    // MARK: - Footer (status + actions)

    private var footer: some View {
        HStack {
            statusLabel
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Join") {
                if let id = selection { join(id) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selection == nil)
        }
        .padding(12)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if service.isLoading {
            Label("Fetching channels… \(service.listings.count) so far",
                  systemImage: "hourglass")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        let total = service.listings.count
        let shown = filtered.count
        if total == 0 {
            return "No cached channels. Click Refresh to issue /LIST."
        }
        let base = (shown == total)
            ? "\(total) channel\(total == 1 ? "" : "s")"
            : "\(shown) of \(total) shown"
        if let when = service.lastUpdated {
            return "\(base) — cached \(Self.formatCacheAge(when))"
        }
        return base
    }

    /// Rough relative age for cache freshness display.
    private static func formatCacheAge(_ when: Date) -> String {
        let delta = Date().timeIntervalSince(when)
        if delta < 60 { return "just now" }
        if delta < 3600 { return "\(Int(delta / 60))m ago" }
        if delta < 86_400 { return "\(Int(delta / 3600))h ago" }
        return "\(Int(delta / 86_400))d ago"
    }

    // MARK: - Filtering / sorting

    private var filtered: [ChannelListService.Listing] {
        let sorted = service.listings.sorted(using: sortOrder)
        guard !searchText.isEmpty else { return sorted }

        if useRegex {
            guard let re = try? NSRegularExpression(pattern: searchText, options: .caseInsensitive) else {
                return sorted   // invalid regex → show all; header shows an error
            }
            return sorted.filter { row in
                let hay = row.name + " " + row.topic
                let range = NSRange(hay.startIndex..., in: hay)
                return re.firstMatch(in: hay, options: [], range: range) != nil
            }
        }
        let needle = searchText.lowercased()
        return sorted.filter {
            $0.name.lowercased().contains(needle) || $0.topic.lowercased().contains(needle)
        }
    }

    private var regexError: String? {
        guard useRegex, !searchText.isEmpty else { return nil }
        do {
            _ = try NSRegularExpression(pattern: searchText, options: .caseInsensitive)
            return nil
        } catch {
            return "Regex error: \(error.localizedDescription)"
        }
    }

    private func join(_ channel: String) {
        onJoin(channel)
        dismiss()
    }
}
