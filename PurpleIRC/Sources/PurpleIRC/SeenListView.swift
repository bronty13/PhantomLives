import SwiftUI

/// Sortable / filterable / regex-able table of all seen entries on a network.
/// Opened via `/seen` with no arguments, or the Bot setup tab's "View seen log"
/// button. Double-click a row (or Enter with a selection) opens a /query with
/// that nick.
struct SeenListView: View {
    let entries: [SeenEntry]
    var onQuery: (String) -> Void
    var onClear: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var useRegex: Bool = false
    @State private var selection: SeenEntry.ID?
    @State private var sortOrder: [KeyPathComparator<SeenEntry>] = [
        KeyPathComparator(\.timestamp, order: .reverse)
    ]
    @State private var confirmClear: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Table(filtered, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Nick", value: \.nick) { row in
                    Text(row.nick)
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 120, ideal: 160)
                TableColumn("Last seen", value: \.timestamp) { row in
                    Text(Self.formatRelative(row.timestamp))
                        .foregroundStyle(.secondary)
                        .help(Self.formatAbsolute(row.timestamp))
                }
                .width(min: 90, ideal: 110)
                TableColumn("Kind", value: \.kind) { row in
                    Text(row.kind)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .width(min: 60, ideal: 70, max: 80)
                TableColumn("Channel") { row in
                    Text(row.channel ?? "")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 90, ideal: 140)
                TableColumn("Detail") { row in
                    Text(row.detail ?? "")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(row.detail ?? "")
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: SeenEntry.ID.self) { ids in
                if let id = ids.first, let row = lookup(id) {
                    Button("Open /query with \(row.nick)") {
                        onQuery(row.nick)
                        dismiss()
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first, let row = lookup(id) {
                    onQuery(row.nick)
                    dismiss()
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 740, minHeight: 460)
    }

    // MARK: - Header / footer

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find in nick, channel, or detail…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Toggle("Regex", isOn: $useRegex)
                    .toggleStyle(.switch)
                    .help("Treat find text as a case-insensitive regular expression")
            }
            if let err = regexError {
                Text(err).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear all seen data", role: .destructive) {
                confirmClear = true
            }
            .confirmationDialog("Erase all seen data for this network?",
                                isPresented: $confirmClear,
                                titleVisibility: .visible) {
                Button("Erase", role: .destructive) { onClear() }
                Button("Cancel", role: .cancel) { }
            }
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Open query") {
                if let id = selection, let row = lookup(id) {
                    onQuery(row.nick)
                    dismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selection == nil)
        }
        .padding(12)
    }

    private var statusText: String {
        let total = entries.count
        let shown = filtered.count
        if total == 0 {
            return "No seen records yet. Enable seen tracking in Setup → Bot, or wait for some channel activity."
        }
        if shown == total { return "\(total) record\(total == 1 ? "" : "s")" }
        return "\(shown) of \(total) shown"
    }

    // MARK: - Filter / sort

    private var filtered: [SeenEntry] {
        let sorted = entries.sorted(using: sortOrder)
        guard !searchText.isEmpty else { return sorted }
        if useRegex {
            guard let re = try? NSRegularExpression(pattern: searchText, options: .caseInsensitive) else {
                return sorted
            }
            return sorted.filter { row in
                let hay = "\(row.nick) \(row.channel ?? "") \(row.detail ?? "") \(row.kind)"
                let r = NSRange(hay.startIndex..., in: hay)
                return re.firstMatch(in: hay, options: [], range: r) != nil
            }
        }
        let needle = searchText.lowercased()
        return sorted.filter {
            $0.nick.lowercased().contains(needle)
                || ($0.channel?.lowercased().contains(needle) ?? false)
                || ($0.detail?.lowercased().contains(needle) ?? false)
                || $0.kind.contains(needle)
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

    private func lookup(_ id: SeenEntry.ID) -> SeenEntry? {
        entries.first { $0.id == id }
    }

    // MARK: - Date formatters

    private static func formatRelative(_ when: Date) -> String {
        let delta = Date().timeIntervalSince(when)
        if delta < 60 { return "just now" }
        if delta < 3600 { return "\(Int(delta / 60))m ago" }
        if delta < 86_400 { return "\(Int(delta / 3600))h ago" }
        return "\(Int(delta / 86_400))d ago"
    }

    private static let absFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
    private static func formatAbsolute(_ when: Date) -> String { absFmt.string(from: when) }
}
