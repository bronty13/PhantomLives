import SwiftUI

/// Searchable reference for every slash command. Invoked by `/help` or
/// `/help <cmd>` (which pre-fills the search box).
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State var searchText: String
    @State private var selection: String?

    init(initialQuery: String = "") {
        self._searchText = State(initialValue: initialQuery)
    }

    private var filtered: [CommandCatalog.Entry] {
        CommandCatalog.search(searchText)
    }

    private var byCategory: [(CommandCatalog.Category, [CommandCatalog.Entry])] {
        Dictionary(grouping: filtered, by: \.category)
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { ($0.key, $0.value.sorted { $0.id < $1.id }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if filtered.isEmpty {
                ContentUnavailableView(
                    "No commands match",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different keyword — or clear the search to see the whole list.")
                )
                .padding(40)
            } else {
                List(selection: $selection) {
                    ForEach(byCategory, id: \.0) { cat, entries in
                        Section(cat.rawValue) {
                            ForEach(entries) { entry in
                                row(entry)
                                    .tag(entry.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 460)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
                .font(.title2)
                .foregroundStyle(Color.purple)
            Text("Command help").font(.title3.weight(.semibold))
            Spacer()
            TextField("Search commands…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            Text("\(filtered.count) of \(CommandCatalog.all.count) shown")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("PurpleIRC v\(AppVersion.short) · build \(AppVersion.build)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    @ViewBuilder
    private func row(_ entry: CommandCatalog.Entry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("/\(entry.id)")
                        .font(.system(.body, design: .monospaced))
                        .bold()
                    if !entry.args.isEmpty {
                        Text(entry.args)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if !entry.aliases.isEmpty {
                        Text("also: " + entry.aliases.map { "/\($0)" }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(entry.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
