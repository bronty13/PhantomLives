import SwiftUI
import AppKit

/// "Information Needed" report — every clip in `new` or `editing` status
/// that's missing at least one of: raw description, categories, go-live
/// date. Designed to be sent back to the creator for follow-up; the
/// **Copy for creator** button packages the list into a clipboard
/// payload prefixed with "Please confirm/provide the following:".
struct InformationNeededReportView: View {
    @EnvironmentObject private var appState: AppState

    @State private var rows: [Row] = []
    @State private var copied: Bool = false

    /// One target clip + the joined-in category list (so we can show
    /// it in the table and emit it in the clipboard payload without
    /// re-querying per row).
    struct Row: Identifiable, Hashable {
        let clip: Clip
        let categories: [String]   // ordered, may be empty
        var id: String { clip.id }

        var descriptionMissing: Bool {
            clip.descriptionRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var categoriesMissing: Bool { categories.isEmpty }
        var goLiveMissing: Bool {
            (clip.goLiveDate ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var anyMissing: Bool {
            descriptionMissing || categoriesMissing || goLiveMissing
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(rows) { row in
                            clipCard(row)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .onAppear { reload() }
        .onChange(of: appState.clips.count)      { _, _ in reload() }
        .onChange(of: appState.categories.count) { _, _ in reload() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Information needed — \(rows.count) clip\(rows.count == 1 ? "" : "s")")
                    .font(.title3.weight(.semibold))
                Text("In new / editing status, missing description, categories, or go-live date.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                copyForCreator()
            } label: {
                Label(copied ? "Copied" : "Copy for creator",
                      systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .disabled(rows.isEmpty)
            .help("Copy a creator-friendly summary to the clipboard")
        }
        .padding(12)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("Nothing to chase — every new/editing clip has its description, categories, and go-live date.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Clip card

    private func clipCard(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // ID — Title [Persona]
            HStack(spacing: 8) {
                ClipIDLabel(id: row.clip.id, style: .caption)
                    .frame(width: 130, alignment: .leading)
                Text("—").foregroundStyle(.tertiary)
                Text(row.clip.title.isEmpty ? "Untitled" : row.clip.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(row.clip.title.isEmpty ? .tertiary : .primary)
                personaPill(row.clip.personaCode)
                Spacer()
                missingBadges(row)
            }

            // Description
            field(
                label: "Description",
                value: row.descriptionMissing ? "Blank" : row.clip.descriptionRaw,
                missing: row.descriptionMissing
            )

            // Categories
            field(
                label: "Categories",
                value: row.categoriesMissing ? "None Defined" : row.categories.joined(separator: ", "),
                missing: row.categoriesMissing
            )

            // Only surface go-live if it's missing — keeps cards short
            // when the clip is just chasing description / categories.
            if row.goLiveMissing {
                field(label: "Go-live date", value: "Not set", missing: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator, lineWidth: 1))
    }

    private func field(label: String, value: String, missing: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.callout)
                .foregroundStyle(missing ? .orange : .primary)
                .italic(missing)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func personaPill(_ code: String) -> some View {
        Text(code)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(appState.color(forPersona: code).opacity(0.2), in: Capsule())
            .foregroundStyle(appState.color(forPersona: code))
    }

    private func missingBadges(_ row: Row) -> some View {
        HStack(spacing: 4) {
            if row.descriptionMissing {
                badge("desc", color: .orange)
            }
            if row.categoriesMissing {
                badge("cats", color: .orange)
            }
            if row.goLiveMissing {
                badge("go-live", color: .orange)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Reload

    private func reload() {
        let result: [Row] = appState.clips
            .filter { !$0.archived }
            .filter { $0.statusEnum == .new || $0.statusEnum == .editing }
            .compactMap { clip in
                let ids = (try? DatabaseService.shared.categoryIds(forClip: clip.id)) ?? []
                let names: [String] = ids.compactMap { cid in
                    appState.categories.first(where: { $0.id == cid })?.name
                }
                let row = Row(clip: clip, categories: names)
                return row.anyMissing ? row : nil
            }
            .sorted { lhs, rhs in
                if lhs.clip.personaCode != rhs.clip.personaCode {
                    return lhs.clip.personaCode < rhs.clip.personaCode
                }
                return lhs.clip.title.localizedCaseInsensitiveCompare(rhs.clip.title) == .orderedAscending
            }
        rows = result
    }

    // MARK: - Copy for creator

    /// Builds the clipboard payload. One block per clip, plain text,
    /// with the requested header and per-clip layout.
    private func copyForCreator() {
        var lines: [String] = ["Please confirm/provide the following:", ""]
        for row in rows {
            let title = row.clip.title.isEmpty ? "Untitled" : row.clip.title
            lines.append("\(row.clip.id) - \(title) [\(row.clip.personaCode)]")
            let desc = row.descriptionMissing ? "Blank" : row.clip.descriptionRaw
            lines.append("Description: \(desc)")
            let cats = row.categoriesMissing ? "None Defined" : row.categories.joined(separator: ", ")
            lines.append("Categories: \(cats)")
            if row.goLiveMissing {
                lines.append("Go-live date: Not set")
            }
            lines.append("")
        }
        let payload = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation { copied = false }
        }
    }
}
