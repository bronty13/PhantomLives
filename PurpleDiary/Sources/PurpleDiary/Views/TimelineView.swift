import SwiftUI

/// The primary view: a chronological list of entries (newest first, grouped by
/// month) on the left, and the selected entry's editor on the right. This is
/// the screen a user lands on, so it doubles as the empty-state onboarding.
struct TimelineView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            entryList
                .frame(width: 320)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Entry list

    private var entryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedEntries, id: \.key) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            EntryRow(entry: entry,
                                     tags: appState.tagsByEntry[entry.id] ?? [],
                                     isSelected: appState.selectedEntryId == entry.id)
                                .onTapGesture { appState.selectedEntryId = entry.id }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        try? appState.deleteEntry(id: entry.id)
                                    } label: {
                                        Label("Delete Entry", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        Text(group.key)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(.bar)
                    }
                }
            }
        }
        .overlay {
            if appState.visibleEntries.isEmpty {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No entries yet")
                .font(.headline)
            Text("Press ⌘N or the pencil in the toolbar to write your first entry.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let id = appState.selectedEntryId,
           let entry = appState.entries.first(where: { $0.id == id }) {
            EntryEditorView(entry: entry)
                .id(entry.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Select an entry, or start a new one.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Grouping

    private struct EntryGroup { let key: String; let entries: [Entry] }

    private var groupedEntries: [EntryGroup] {
        let fmt = DateFormatter()
        fmt.dateFormat = "LLLL yyyy"
        let sorted = appState.visibleEntries.sorted { $0.date > $1.date }
        var order: [String] = []
        var buckets: [String: [Entry]] = [:]
        for entry in sorted {
            let key = fmt.string(from: entry.dateValue)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(entry)
        }
        return order.map { EntryGroup(key: $0, entries: buckets[$0] ?? []) }
    }
}

/// One row in the timeline list: day number, title (or a body snippet), mood,
/// and tag chips.
struct EntryRow: View {
    let entry: Entry
    let tags: [Tag]
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Text(dayNumber)
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text(weekday)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if !snippet.isEmpty {
                    Text(snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !tags.isEmpty || entry.mood != .unset {
                    HStack(spacing: 4) {
                        if entry.mood != .unset {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow)
                            Text("\(entry.mood.rawValue)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(tags.prefix(3)) { tag in
                            Text(tag.name)
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background((Color(hex: tag.colorHex) ?? .gray).opacity(0.25),
                                            in: Capsule())
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
    }

    private var displayTitle: String {
        entry.title.isEmpty ? (snippetSource.isEmpty ? "Untitled" : snippetSource) : entry.title
    }

    private var snippetSource: String {
        entry.bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var snippet: String {
        // Only show a body snippet when there's a real title (else it's the title).
        guard !entry.title.isEmpty else { return "" }
        return snippetSource.replacingOccurrences(of: "\n", with: " ")
    }

    private var dayNumber: String {
        let f = DateFormatter(); f.dateFormat = "d"
        return f.string(from: entry.dateValue)
    }

    private var weekday: String {
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f.string(from: entry.dateValue)
    }
}
