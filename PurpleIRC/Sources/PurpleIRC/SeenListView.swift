import SwiftUI

/// Sortable / filterable / regex-able table of all seen entries on a network.
/// Opened via `/seen` with no arguments, or the Bot setup tab's "View seen log"
/// button. Double-click a row (or Enter with a selection) opens a /query with
/// that nick. Right-click → "View history" opens a sheet listing every
/// recorded sighting for that nick (host changes, channel hops, etc.).
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
    /// Selected entry for the "View history" detail sheet. nil = sheet hidden.
    @State private var historyEntry: SeenEntry? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Table(filtered, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Nick", value: \.nick) { row in
                    Text(row.nick)
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 110, ideal: 140)
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
                TableColumn("User@Host") { row in
                    Text(row.lastUserHost ?? "")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(row.lastUserHost ?? "")
                }
                .width(min: 120, ideal: 180)
                TableColumn("Channel") { row in
                    Text(row.channel ?? "")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 90, ideal: 130)
                TableColumn("History") { row in
                    Text("\(row.history.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .help("Total recorded sightings on file")
                }
                .width(min: 50, ideal: 60, max: 70)
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
                    Button("View history (\(row.history.count) sighting\(row.history.count == 1 ? "" : "s"))") {
                        historyEntry = row
                    }
                    .disabled(row.history.isEmpty)
                    if let host = row.lastUserHost {
                        Divider()
                        Button("Copy user@host") {
                            #if canImport(AppKit)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(host, forType: .string)
                            #endif
                        }
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
        .frame(minWidth: 860, minHeight: 480)
        .sheet(item: $historyEntry) { entry in
            SeenHistorySheet(entry: entry)
        }
    }

    // MARK: - Header / footer

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find in nick, host, channel, or detail…", text: $searchText)
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
            Button("View history") {
                if let id = selection, let row = lookup(id) {
                    historyEntry = row
                }
            }
            .disabled(selection == nil || (selection.flatMap { lookup($0)?.history.isEmpty } ?? true))
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
                let hay = "\(row.nick) \(row.channel ?? "") \(row.detail ?? "") \(row.kind) \(row.lastUserHost ?? "")"
                let r = NSRange(hay.startIndex..., in: hay)
                return re.firstMatch(in: hay, options: [], range: r) != nil
            }
        }
        let needle = searchText.lowercased()
        return sorted.filter {
            $0.nick.lowercased().contains(needle)
                || ($0.channel?.lowercased().contains(needle) ?? false)
                || ($0.detail?.lowercased().contains(needle) ?? false)
                || ($0.lastUserHost?.lowercased().contains(needle) ?? false)
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

    static func formatRelative(_ when: Date) -> String {
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
    static func formatAbsolute(_ when: Date) -> String { absFmt.string(from: when) }
}

// MARK: - History detail sheet

/// Detail sheet showing every recorded sighting for one nick. Highlights
/// host changes (different user@host than the previous sighting) so the
/// user can spot when a familiar nick connects from somewhere new — useful
/// for the "is this the same person?" question.
struct SeenHistorySheet: View {
    let entry: SeenEntry
    @Environment(\.dismiss) private var dismiss

    /// Distinct user@host values across the captured history — quick read
    /// on whether the nick has been stable or hopping.
    private var distinctHosts: [String] {
        var seen = Set<String>(); var out: [String] = []
        for s in entry.history {
            if let h = s.userHost, !h.isEmpty, seen.insert(h).inserted {
                out.append(h)
            }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(minWidth: 620, minHeight: 460)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title2)
                .foregroundStyle(Color.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.nick).font(.title3.weight(.semibold))
                    .font(.system(.title3, design: .monospaced))
                Text("\(entry.history.count) sighting\(entry.history.count == 1 ? "" : "s") · \(distinctHosts.count) distinct host\(distinctHosts.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if entry.history.isEmpty {
                    Text("No history captured yet.")
                        .foregroundStyle(.secondary)
                        .padding(24)
                } else {
                    ForEach(Array(entry.history.enumerated()), id: \.offset) { (idx, sighting) in
                        sightingRow(idx: idx, sighting: sighting)
                        if idx < entry.history.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sightingRow(idx: Int, sighting: SeenSighting) -> some View {
        // Mark host changes — when this sighting's host differs from the
        // immediately-previous (newer) sighting's host. Visual cue helps
        // the user spot when a nick switched IP/cloak.
        let previousHost = idx > 0 ? entry.history[idx - 1].userHost : nil
        let isHostChange = sighting.userHost != nil
            && previousHost != nil
            && sighting.userHost != previousHost

        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(SeenListView.formatRelative(sighting.timestamp))
                    .font(.caption.weight(.semibold))
                Text(SeenListView.formatAbsolute(sighting.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 110, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(kindBadge(for: sighting.kind))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(kindColor(for: sighting.kind).opacity(0.18)))
                        .foregroundStyle(kindColor(for: sighting.kind))
                    if let channel = sighting.channel {
                        Text(channel)
                            .font(.system(.body, design: .monospaced))
                    }
                    if isHostChange {
                        Label("host changed", systemImage: "arrow.triangle.swap")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.20)))
                            .foregroundStyle(.orange)
                    }
                }
                if let host = sighting.userHost {
                    Text(host)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let detail = sighting.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func kindBadge(for kind: String) -> String {
        switch kind {
        case "msg": return "msg"
        case "join": return "join"
        case "part": return "part"
        case "quit": return "quit"
        case "nick": return "nick"
        default: return kind
        }
    }

    private func kindColor(for kind: String) -> Color {
        switch kind {
        case "msg":  return .blue
        case "join": return .green
        case "part": return .orange
        case "quit": return .red
        case "nick": return .purple
        default:     return .secondary
        }
    }
}
