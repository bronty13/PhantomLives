import SwiftUI

/// Modal viewer over `AppLog.shared`. The list is bound to `changeCount` so
/// SwiftUI redraws on every emit without re-diffing the array; level filter
/// + free-text search narrow what's visible. "Copy" hands the user a
/// timestamped, level-prefixed plaintext snapshot suitable for bug reports.
struct LogViewerView: View {
    @ObservedObject var log: AppLog = .shared
    @State private var minimum: LogLevel = .info
    @State private var search: String = ""
    @State private var autoscroll: Bool = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            // Keep viewer state in sync with the live filter so the picker
            // shows what's actually being retained.
            minimum = log.minimumLevel
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            Picker("Minimum", selection: $minimum) {
                ForEach(LogLevel.allCases, id: \.self) { lvl in
                    Text(lvl.label).tag(lvl)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .onChange(of: minimum) { _, new in
                log.minimumLevel = new
            }

            TextField("Filter (text, category, level)", text: $search)
                .textFieldStyle(.roundedBorder)

            Toggle("Autoscroll", isOn: $autoscroll)

            Button("Refresh") { log.loadFromDisk() }
            Button("Copy") { copyVisibleAsText() }
            Button("Clear", role: .destructive) { log.clear() }
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(10)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            // `id: log.changeCount` forces SwiftUI to refresh the list view
            // when new records arrive without us holding a `@Published` array
            // (which would copy the whole ring on every keystroke).
            List(filteredEntries) { rec in
                LogRow(record: rec)
                    .id(rec.id)
                    .listRowSeparator(.hidden)
            }
            .id(log.changeCount)
            .listStyle(.plain)
            .onChange(of: log.changeCount) { _, _ in
                guard autoscroll, let last = filteredEntries.last else { return }
                withAnimation(.linear(duration: 0.05)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(filteredEntries.count) of \(log.entries.count) records")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Encrypted on disk when the keystore is unlocked. Locked sessions log in-memory only.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    /// Apply level-floor + text filter. Search matches level label, category,
    /// or message — case-insensitive.
    private var filteredEntries: [AppLogRecord] {
        let lower = search.trimmingCharacters(in: .whitespaces).lowercased()
        return log.entries.filter { rec in
            guard rec.level >= minimum else { return false }
            if lower.isEmpty { return true }
            return rec.message.lowercased().contains(lower)
                || rec.category.lowercased().contains(lower)
                || rec.level.label.lowercased().contains(lower)
        }
    }

    private func copyVisibleAsText() {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let body = filteredEntries.map { rec in
            "\(f.string(from: rec.timestamp))  \(rec.level.label.padding(toLength: 6, withPad: " ", startingAt: 0))  [\(rec.category)] \(rec.message)"
        }.joined(separator: "\n")
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body, forType: .string)
        #endif
    }
}

/// A single row. Pulled out so the list can compose efficiently and the
/// timestamp formatter is cached per row body evaluation.
private struct LogRow: View {
    let record: AppLogRecord

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timeString)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(record.level.label)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(record.level.tint))
                .frame(width: 60, alignment: .leading)
            Text(record.category)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(record.message)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: record.timestamp)
    }
}
