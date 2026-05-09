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
    @State private var personaFilter: String = ""        // empty = all personas
    @State private var selection: Clip.ID?
    @State private var sortOrder: [KeyPathComparator<Clip>] = [
        KeyPathComparator(\Clip.contentDate, order: .forward)
    ]
    @State private var showingVerificationWorkflow: Bool = false

    var body: some View {
        EdPageShell(
            eyebrow: "Section · Editing",
            headline: "Editing queue.",
            emphasized: "queue",
            deck: deckText,
            trailing: AnyView(
                Button {
                    showingVerificationWorkflow = true
                } label: {
                    Text("RUN FILE VERIFICATION")
                }
                .buttonStyle(EdGhostButtonStyle())
                .disabled(filteredClips.isEmpty)
                .help("Walk through the visible queue one clip at a time, auditing files for each.")
            )
        ) {
            HSplitView {
                VStack(spacing: 0) {
                    filterBar
                    EdHairline(color: EdColor.ink(0.18))
                    queueTable
                }
                .frame(minWidth: 540)

                ClipDetailView(clipId: selection)
                    .frame(minWidth: 480)
            }
        }
        .sheet(isPresented: $showingVerificationWorkflow) {
            FileAuditWorkflow(clips: filteredClips)
        }
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

    // MARK: - Deck

    private var deckText: String {
        let n = filteredClips.count
        if n == 0 { return "Nothing in scope. Adjust filters or check Clips." }
        return "\(n) clip\(n == 1 ? "" : "s") in flight. Pick one and the editor opens to the right."
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach([ClipStatus.new, .editing, .toPost, .posting], id: \.self) { status in
                statusToggle(status)
            }

            Rectangle().fill(EdColor.ink(0.18)).frame(width: 1, height: 18)

            Picker("Persona", selection: $personaFilter) {
                Text("All personas").tag("")
                ForEach(appState.personas) { p in
                    Text(p.code).tag(p.code)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)

            Spacer()
            Text("\(filteredClips.count) CLIPS")
                .font(EdFont.mono(10.5))
                .tracking(0.84)
                .foregroundStyle(EdColor.ink(0.55))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(EdColor.bone)
    }

    private func statusToggle(_ status: ClipStatus) -> some View {
        let count = appState.clips.filter { !$0.archived && $0.statusEnum == status }.count
        let active = statusFilter.contains(status)
        return Button {
            if active { statusFilter.remove(status) }
            else      { statusFilter.insert(status) }
        } label: {
            HStack(spacing: 6) {
                Text(status.label.uppercased())
                    .font(EdFont.mono(10.5, weight: .semibold))
                    .tracking(0.84)
                Text(String(format: "%02d", count))
                    .font(EdFont.mono(10.5))
                    .foregroundStyle(active ? EdColor.acid.opacity(0.9) : EdColor.ink(0.55))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(active ? EdColor.acid : EdColor.ink)
            .background(active ? EdColor.ink : Color.clear)
            .overlay(Rectangle().strokeBorder(EdColor.ink, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Queue table

    private var filteredClips: [Clip] {
        var result = appState.clips
            .filter { !$0.archived }
            .filter { statusFilter.contains($0.statusEnum) }

        if !personaFilter.isEmpty {
            result = result.filter {
                $0.personaCode.caseInsensitiveCompare(personaFilter) == .orderedSame
            }
        }

        return result.sorted(using: sortOrder)
    }

    private var queueTable: some View {
        // Every column is sortable — `value:` keypaths drive the sort order.
        // Computed-only columns (Status, Editing progress) sort by a derived
        // string we attach explicitly via `value: \ClipExt.x` style helpers.
        Table(filteredClips, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Title", value: \Clip.title) { clip in
                Text(clip.title.isEmpty ? "—" : clip.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(clip.title.isEmpty ? .tertiary : .primary)
                    .help(clip.title)
            }
            .width(min: 240, ideal: 460)

            TableColumn("Persona", value: \Clip.personaCode) { clip in
                PersonaPill(code: clip.personaCode)
            }
            .width(min: 86, ideal: 96)

            TableColumn("Status", value: \Clip.status) { clip in
                statusCell(clip.statusEnum)
            }
            .width(min: 96, ideal: 104)

            TableColumn("Editing", value: \Clip.editingProgressKey) { clip in
                editingProgressCell(clip)
            }
            .width(min: 96, ideal: 104)

            TableColumn("Recorded", value: \Clip.contentDate, comparator: OptionalStringComparator()) { clip in
                Text(clip.contentDate ?? "—")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .width(min: 92, ideal: 100)

            TableColumn("Go-Live", value: \Clip.goLiveDate, comparator: OptionalStringComparator()) { clip in
                Text(clip.goLiveDate ?? "—")
                    .font(.caption.monospaced())
                    .foregroundStyle((clip.goLiveDate ?? "").isEmpty ? .tertiary : .secondary)
            }
            .width(min: 92, ideal: 100)

            TableColumn("Length", value: \Clip.lengthSecondsKey) { clip in
                Text(DurationFormatter.format(clip.lengthSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(clip.lengthSeconds == nil ? .tertiary : .primary)
            }
            .width(min: 56, ideal: 68)

            TableColumn("ID", value: \Clip.id) { clip in
                ClipIDLabel(id: clip.id, style: .caption)
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

// MARK: - Sort helpers

/// Comparator for `String?` columns that sorts nils at the end regardless of
/// direction. Empty strings are treated as nil for sort purposes.
private struct OptionalStringComparator: SortComparator {
    var order: SortOrder = .forward

    func compare(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
        let l = (lhs ?? "").isEmpty ? nil : lhs
        let r = (rhs ?? "").isEmpty ? nil : rhs
        switch (l, r) {
        case (nil, nil): return .orderedSame
        case (nil, _):   return .orderedDescending   // nils to the end
        case (_, nil):   return .orderedAscending
        case let (a?, b?):
            let raw = a.compare(b)
            return order == .forward ? raw : raw.flipped
        default:         return .orderedSame
        }
    }
}

private extension ComparisonResult {
    var flipped: ComparisonResult {
        switch self {
        case .orderedAscending:  return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame:       return .orderedSame
        }
    }
}

// MARK: - Sort key helpers on Clip

private extension Clip {
    /// Sortable key for the editing-progress column: "1/3", "2/3", "3/3" etc.
    /// Lex sort over zero-padded counts gets the right order.
    var editingProgressKey: String {
        let fcp  = !(fcpProjectFolder ?? "").isEmpty
        let prod = !(productionFolder ?? "").isEmpty
        let dur  = lengthSeconds != nil
        return String([fcp, prod, dur].filter { $0 }.count)
    }

    /// Sortable key for the length column. nils sort last as "9999999".
    var lengthSecondsKey: Int {
        lengthSeconds ?? Int.max
    }
}
