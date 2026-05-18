import SwiftUI

/// Searchable keyboard shortcuts cheat sheet. Reads `Shortcuts.all`
/// (the same source of truth `SHORTCUTS.md` is generated from), so
/// this view never drifts out of sync with the documented surface.
struct ShortcutsCheatSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(filteredByGroup, id: \.0) { group, items in
                        groupSection(group: group, items: items)
                    }
                    if filteredByGroup.isEmpty {
                        Text("No shortcuts match “\(query)”.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 40)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 540)
    }

    private var header: some View {
        HStack {
            Text("Keyboard Shortcuts").font(.headline)
            Spacer()
            Text("v\(AppVersion.marketing)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter shortcuts…", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var footer: some View {
        HStack {
            Text("\(filteredCount) of \(Shortcuts.all.count) shortcuts")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private func groupSection(group: ShortcutGroup, items: [Shortcut]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.rawValue)
                .font(.headline)
                .foregroundStyle(.primary)
            ForEach(items) { s in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(s.combo)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15),
                                      in: RoundedRectangle(cornerRadius: 4))
                        .frame(minWidth: 110, alignment: .leading)
                    Text(s.action)
                    Spacer()
                }
                .font(.body)
            }
        }
    }

    // MARK: - Filtering

    private var filteredByGroup: [(ShortcutGroup, [Shortcut])] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return Shortcuts.byGroup() }
        return Shortcuts.byGroup().compactMap { group, items in
            let hits = items.filter {
                $0.combo.lowercased().contains(trimmed)
                || $0.action.lowercased().contains(trimmed)
                || group.rawValue.lowercased().contains(trimmed)
            }
            return hits.isEmpty ? nil : (group, hits)
        }
    }

    private var filteredCount: Int {
        filteredByGroup.reduce(0) { $0 + $1.1.count }
    }
}
