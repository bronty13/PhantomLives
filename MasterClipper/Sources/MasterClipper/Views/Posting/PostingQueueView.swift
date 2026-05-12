import SwiftUI
import MasterClipperCore

/// Workflow queue for clips that are post-ready but not yet fully posted.
/// Mirrors `EditingQueueView` — same master/detail layout, same editor on
/// the right — but defaults to `to_post + posting` status and shows posting
/// progress (X of N scoped sites done) instead of editing-stage progress.
///
/// Use this when you want to focus on the "what's ready to push out" pile
/// without the noise of clips still in editing. The per-site batch wizard
/// (Posting Batch) is still the right tool for actually marking sites
/// posted; this is the at-a-glance backlog.
struct PostingQueueView: View {
    @EnvironmentObject private var appState: AppState

    @State private var statusFilter: Set<ClipStatus> = [.toPost, .posting]
    @State private var personaFilter: String = ""
    @State private var selection: Clip.ID?
    @State private var sortOrder: [KeyPathComparator<Clip>] = [
        KeyPathComparator(\Clip.goLiveDate, order: .forward)
    ]
    /// clipId → set of siteIds the clip has been posted to. Loaded once and
    /// refreshed when the clip count changes — cheap enough that we don't
    /// need a per-clip diff.
    @State private var postedByClip: [String: Set<Int64>] = [:]
    @State private var showingVerificationWorkflow: Bool = false

    var body: some View {
        EdPageShell(
            eyebrow: "Section · Posting",
            headline: "Ready to push.",
            emphasized: "push",
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
            refreshPostings()
            if selection == nil { selection = filteredClips.first?.id }
        }
        .onChange(of: appState.clips.count) { _, _ in refreshPostings() }
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
        if n == 0 { return "Nothing in scope. Adjust filters or check Editing." }
        return "\(n) clip\(n == 1 ? "" : "s") ready or in posting. Mark sites or open Batch."
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach([ClipStatus.toPost, .posting, .production], id: \.self) { status in
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

    // MARK: - Queue

    private var filteredClips: [Clip] {
        var result = appState.clips
            .filter { !$0.archived }
            .filter { !$0.postingExcluded }
            .filter { statusFilter.contains($0.statusEnum) }
        if !personaFilter.isEmpty {
            result = result.filter {
                $0.personaCode.caseInsensitiveCompare(personaFilter) == .orderedSame
            }
        }
        return result.sorted(using: sortOrder)
    }

    private var queueTable: some View {
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

            TableColumn("Posting") { clip in
                postingProgressCell(clip)
            }
            .width(min: 160, ideal: 220)

            TableColumn("Go-Live", value: \Clip.goLiveDate, comparator: OptionalStringComparator()) { clip in
                Text(clip.goLiveDate ?? "—")
                    .font(.caption.monospaced())
                    .foregroundStyle((clip.goLiveDate ?? "").isEmpty ? .tertiary : .secondary)
            }
            .width(min: 92, ideal: 100)

            TableColumn("Length", value: \Clip.lengthSecondsKeyPosting) { clip in
                Text(DurationFormatter.format(clip.lengthSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(clip.lengthSeconds == nil ? .tertiary : .primary)
            }
            .width(min: 56, ideal: 68)

            TableColumn("Price", value: \Clip.priceCentsKeyPosting) { clip in
                Text(clip.priceCents.map { String(format: "$%.2f", Double($0) / 100) } ?? "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(clip.priceCents == nil ? .tertiary : .primary)
            }
            .width(min: 64, ideal: 72)

            TableColumn("ID", value: \Clip.id) { clip in
                ClipIDLabel(id: clip.id, style: .caption)
            }
            .width(min: 130, ideal: 140)
        }
    }

    // MARK: - Posting-progress cell

    /// Per-site mini-pill row: site code + ✓/○. Hovering / clicking the
    /// row jumps into the editor, where the existing PostingGrid handles
    /// flipping individual sites.
    private func postingProgressCell(_ clip: Clip) -> some View {
        let sites = scopedSites(for: clip)
        let posted = postedByClip[clip.id] ?? []
        let postedCount = sites.filter { posted.contains($0.id ?? -1) }.count
        return HStack(spacing: 4) {
            ForEach(sites) { site in
                sitePill(site: site, posted: posted.contains(site.id ?? -1))
            }
            Text("\(postedCount)/\(sites.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func sitePill(site: Site, posted: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: posted ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
                .foregroundStyle(posted ? .green : Color(NSColor.tertiaryLabelColor))
            Text(site.code)
                .font(.caption2.monospaced())
                .foregroundStyle(posted ? .primary : .secondary)
        }
        .padding(.horizontal, 5).padding(.vertical, 1)
        .background(
            (posted ? Color.green : Color.gray).opacity(posted ? 0.15 : 0.10),
            in: Capsule()
        )
        .help(posted ? "\(site.displayName) — posted" : "\(site.displayName) — pending")
    }

    private func scopedSites(for clip: Clip) -> [Site] {
        appState.sites
            .filter { !$0.archived }
            .filter { $0.appliesTo(personaCode: clip.personaCode) }
            .sorted { $0.sortOrder < $1.sortOrder }
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

    // MARK: - Data

    private func refreshPostings() {
        if let map = try? PostingService.postedSitesByClip() {
            postedByClip = map
        }
    }
}

// MARK: - Sort comparator

private struct OptionalStringComparator: SortComparator {
    var order: SortOrder = .forward

    func compare(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
        let l = (lhs ?? "").isEmpty ? nil : lhs
        let r = (rhs ?? "").isEmpty ? nil : rhs
        switch (l, r) {
        case (nil, nil): return .orderedSame
        case (nil, _):   return .orderedDescending
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

private extension Clip {
    /// Length sort key — nils sort last as Int.max.
    var lengthSecondsKeyPosting: Int { lengthSeconds ?? Int.max }

    /// Price sort key — nils sort last so unpriced clips fall to the
    /// bottom regardless of sort direction.
    var priceCentsKeyPosting: Int { priceCents ?? Int.max }
}
