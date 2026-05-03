import SwiftUI

/// Workflow queue for clips that aren't yet fully posted. Master/detail view:
/// the table on the left lists clips by pipeline status, and the right pane
/// shows the standard `ClipEditView` so the user can fill in editing artifacts
/// (FCP folder, production folder, length) inline.
///
/// Status auto-advances on save: filling all three editing fields promotes the
/// clip from `editing` → `to_post`; marking sites posted later moves it through
/// `posting` → `production`.
struct EditingQueueView: View {
    @EnvironmentObject private var appState: AppState

    @State private var statusFilter: Set<ClipStatus> = [.new, .editing, .toPost]
    @State private var selection: Clip.ID?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                filterBar
                Divider()
                queueTable
            }
            .frame(minWidth: 540)

            ClipDetailView(clipId: selection)
                .frame(minWidth: 480)
        }
        .navigationTitle("Editing Queue")
        .onAppear {
            if selection == nil { selection = filteredClips.first?.id }
        }
        .onChange(of: appState.focusedClipId) { _, newValue in
            if let id = newValue {
                selection = id
                appState.focusedClipId = nil
            }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach([ClipStatus.new, .editing, .toPost, .posting], id: \.self) { status in
                statusToggle(status)
            }
            Spacer()
            Text("\(filteredClips.count) clips")
                .font(.caption).foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(10)
        .background(.background.secondary)
    }

    private func statusToggle(_ status: ClipStatus) -> some View {
        let count = appState.clips.filter { !$0.archived && $0.statusEnum == status }.count
        let active = statusFilter.contains(status)
        return Button {
            if active { statusFilter.remove(status) }
            else      { statusFilter.insert(status) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: status.systemImage).font(.caption)
                Text(status.label)
                Text("(\(count))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                active ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.15),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Queue table

    private var filteredClips: [Clip] {
        appState.clips
            .filter { !$0.archived }
            .filter { statusFilter.contains($0.statusEnum) }
            .sorted { lhs, rhs in
                if lhs.statusEnum.sortOrder != rhs.statusEnum.sortOrder {
                    return lhs.statusEnum.sortOrder < rhs.statusEnum.sortOrder
                }
                return (lhs.contentDate ?? lhs.createdAt) < (rhs.contentDate ?? rhs.createdAt)
            }
    }

    private var queueTable: some View {
        // Title is column 1 with the same big-font / wide-min treatment as
        // the Clips list — the editing queue should read at a glance.
        Table(filteredClips, selection: $selection) {
            TableColumn("Title") { clip in
                Text(clip.title.isEmpty ? "—" : clip.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(clip.title.isEmpty ? .tertiary : .primary)
                    .help(clip.title)
            }
            .width(min: 240, ideal: 460)

            TableColumn("Persona") { clip in
                PersonaPill(code: clip.personaCode)
            }
            .width(min: 86, ideal: 96)

            TableColumn("Status") { clip in
                statusCell(clip.statusEnum)
            }
            .width(min: 96, ideal: 104)

            TableColumn("Editing") { clip in
                editingProgressCell(clip)
            }
            .width(min: 96, ideal: 104)

            TableColumn("Recorded") { clip in
                Text(clip.contentDate ?? "—")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .width(min: 92, ideal: 100)

            TableColumn("Length") { clip in
                Text(DurationFormatter.format(clip.lengthSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(clip.lengthSeconds == nil ? .tertiary : .primary)
            }
            .width(min: 56, ideal: 68)

            TableColumn("ID") { clip in
                Text(clip.id).font(.caption.monospaced())
            }
            .width(min: 130, ideal: 140)
        }
    }

    // MARK: - Cells

    private func statusCell(_ s: ClipStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: s.systemImage).font(.caption2)
            Text(s.label).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(statusColor(s).opacity(0.22), in: Capsule())
        .foregroundStyle(statusColor(s))
    }

    private func editingProgressCell(_ clip: Clip) -> some View {
        let fcp  = !(clip.fcpProjectFolder ?? "").isEmpty
        let prod = !(clip.productionFolder ?? "").isEmpty
        let dur  = clip.lengthSeconds != nil
        let count = [fcp, prod, dur].filter { $0 }.count
        return HStack(spacing: 3) {
            indicator(filled: fcp, label: "FCP")
            indicator(filled: prod, label: "Prod")
            indicator(filled: dur, label: "Len")
            Text("\(count)/3")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func indicator(filled: Bool, label: String) -> some View {
        Image(systemName: filled ? "checkmark.circle.fill" : "circle")
            .font(.caption2)
            .foregroundStyle(filled ? .green : Color(NSColor.tertiaryLabelColor))
            .help(filled ? "\(label) filled" : "\(label) missing")
    }

    private func statusColor(_ s: ClipStatus) -> Color {
        switch s {
        case .new:        return .gray
        case .editing:    return .orange
        case .toPost:     return .blue
        case .posting:    return .purple
        case .production: return .green
        case .archived:   return .secondary
        }
    }
}
