import SwiftUI

struct ClipHistoryView: View {
    let clipId: String
    @State private var entries: [ClipHistoryEntry] = []
    @State private var error: String?
    @State private var expanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if entries.isEmpty {
                Text("No changes recorded yet.")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 8) {
                                Text(entry.fieldLabel)
                                    .font(.caption.weight(.semibold))
                                Text(displayTime(entry.changedAt))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                            HStack(alignment: .top, spacing: 6) {
                                Text("from")
                                    .font(.caption2).foregroundStyle(.tertiary)
                                Text(short(entry.oldValue))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .strikethrough()
                                    .lineLimit(2)
                            }
                            HStack(alignment: .top, spacing: 6) {
                                Text("to  ")
                                    .font(.caption2).foregroundStyle(.tertiary)
                                Text(short(entry.newValue))
                                    .font(.caption.monospaced())
                                    .lineLimit(2)
                            }
                            Divider()
                        }
                    }
                }
                .padding(.top, 4)
            }
        } label: {
            HStack {
                Text("Change history")
                    .font(.headline)
                Text("(\(entries.count))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { reload() }
        .onChange(of: clipId) { _, _ in reload() }
    }

    func reload() {
        do {
            entries = try DatabaseService.shared.fetchHistory(forClip: clipId)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func short(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "—" }
        if s.count > 200 { return String(s.prefix(197)) + "…" }
        return s.replacingOccurrences(of: "\n", with: " ↩ ")
    }

    private func displayTime(_ iso: String) -> String {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        parser.locale = Locale(identifier: "en_US_POSIX")
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        if let d = parser.date(from: iso) { return display.string(from: d) }
        return iso
    }
}
