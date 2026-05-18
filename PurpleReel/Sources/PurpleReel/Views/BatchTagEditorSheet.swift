import SwiftUI

/// ⌘⇧T sheet — Kyno's batch tag editor. Operates on the current
/// multi-selection (or the primary selection as fallback). Tag-add
/// is additive; tag-remove operates on every selected asset that
/// has the tag.
///
/// Tags that are on EVERY selected asset render as solid pills; a
/// tag on a strict subset shows a "partial" badge so the user knows
/// removing it only touches some of the selection. This is the
/// behavior reviewers expected from Kyno's editor and that Kyno
/// itself never quite nailed.
struct BatchTagEditorSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var draft: String = ""
    @State private var summary: [(name: String, partial: Bool)] = []
    @State private var status: String = ""

    /// Filtered autocomplete from `knownTagNames`. Excludes whatever
    /// the user has already typed (case-insensitive) and tags
    /// already on every target.
    private var autocomplete: [String] {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lower = trimmed.lowercased()
        let presentEverywhere = Set(summary.filter { !$0.partial }.map { $0.name.lowercased() })
        return appState.knownTagNames
            .filter { $0.lowercased().contains(lower)
                       && !presentEverywhere.contains($0.lowercased()) }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            currentTagsSection
            Divider()
            addTagSection
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 480, height: 480)
        .onAppear(perform: refresh)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Edit Tags")
                .font(.title3.weight(.semibold))
            Text(targetLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var currentTagsSection: some View {
        if summary.isEmpty {
            Text("No tags applied to the selection.")
                .foregroundStyle(.secondary)
                .font(.callout)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("On the selection")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                let columns = [GridItem(.adaptive(minimum: 110, maximum: 200), spacing: 6)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(summary, id: \.name) { item in
                        Button {
                            appState.batchRemoveTag(name: item.name)
                            status = "Removed “\(item.name)” from \(appState.batchTagTargets.count) clip(s)."
                            refresh()
                        } label: {
                            HStack(spacing: 4) {
                                Text(item.name).font(.caption)
                                if item.partial {
                                    Text("partial").font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.orange.opacity(0.30),
                                                     in: Capsule())
                                }
                                Image(systemName: "xmark").font(.system(size: 9))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                item.partial
                                    ? Color.orange.opacity(0.15)
                                    : Color.accentColor.opacity(0.18),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var addTagSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add a tag")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Type a tag and press Return", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commitDraft)
            if !autocomplete.isEmpty {
                FlowChips(values: autocomplete) { tag in
                    draft = tag
                    commitDraft()
                }
            }
            if !status.isEmpty {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Actions

    private var targetLabel: String {
        let n = appState.batchTagTargets.count
        if n == 0 { return "No clip selected." }
        if n == 1 {
            return "Applies to “\(appState.batchTagTargets.first?.filename ?? "selected clip")”."
        }
        return "Applies to \(n) clips."
    }

    private func commitDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let n = appState.batchAddTag(name: trimmed)
        status = "Added “\(trimmed)” to \(n) clip(s)."
        draft = ""
        refresh()
    }

    private func refresh() {
        summary = appState.batchTagSummary()
    }
}

/// Horizontal flow of short tag pills — used for the autocomplete
/// row beneath the tag-entry field.
private struct FlowChips: View {
    let values: [String]
    var onPick: (String) -> Void

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 80, maximum: 160), spacing: 4)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(values, id: \.self) { v in
                Button { onPick(v) } label: {
                    Text(v)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15),
                                     in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
