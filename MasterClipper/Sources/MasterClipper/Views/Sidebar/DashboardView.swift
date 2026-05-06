import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    @State private var allPostings: [ClipPosting] = []
    @State private var filter: Filter = .incomplete

    enum Filter: String, CaseIterable, Hashable {
        case all, incomplete, completed
        var label: String {
            switch self {
            case .all:        return "All"
            case .incomplete: return "Incomplete"
            case .completed:  return "Completed"
            }
        }
    }

    private struct ClipSummary: Identifiable {
        let clip: Clip
        let scopedSites: [Site]
        let postedSiteIds: Set<Int64>
        var id: String { clip.id }

        var totalScoped: Int { scopedSites.count }
        var totalPosted: Int { scopedSites.compactMap(\.id).filter { postedSiteIds.contains($0) }.count }
        var isComplete: Bool { totalScoped > 0 && totalPosted == totalScoped }
        var notPosted: Bool { totalPosted == 0 }
        var partial: Bool   { totalPosted > 0 && !isComplete }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Dashboard")
                    .font(.largeTitle.weight(.semibold))

                topStats
                perTargetProgress
                clipMatrix
            }
            .padding(28)
        }
        .onAppear(perform: reload)
        .onChange(of: appState.clips.count) { _, _ in reload() }
    }

    // MARK: - Reload

    private func reload() {
        do {
            allPostings = try DatabaseService.shared.dbPool.read { db in
                try ClipPosting.fetchAll(db)
            }
        } catch {
            allPostings = []
        }
    }

    // MARK: - Computed

    private var summaries: [ClipSummary] {
        let postedByClip: [String: Set<Int64>] = Dictionary(
            grouping: allPostings.filter { $0.statusEnum == .posted },
            by: \.clipId
        ).mapValues { Set($0.map(\.siteId)) }

        return appState.clips
            .filter { !$0.archived }
            .filter { !$0.postingExcluded }    // not-to-be-posted clips don't belong on the matrix
            .map { clip in
                let scoped = appState.sites
                    .filter { !$0.archived && $0.appliesTo(personaCode: clip.personaCode) }
                    .sorted { $0.sortOrder < $1.sortOrder }
                let posted = postedByClip[clip.id] ?? []
                return ClipSummary(clip: clip, scopedSites: scoped, postedSiteIds: posted)
            }
    }

    private var filteredSummaries: [ClipSummary] {
        let all = summaries
        switch filter {
        case .all:        return all
        case .incomplete: return all.filter { !$0.isComplete }
        case .completed:  return all.filter { $0.isComplete }
        }
    }

    // MARK: - Top stats

    private var topStats: some View {
        let s = summaries
        let complete = s.filter(\.isComplete).count
        let partial  = s.filter(\.partial).count
        let none     = s.filter(\.notPosted).count
        let scopeless = s.filter { $0.totalScoped == 0 }.count

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
            statCard(label: "Clips",        value: "\(s.count)",
                     system: "film.stack.fill", color: .accentColor,
                     filter: .all)
            statCard(label: "Fully posted", value: "\(complete)",
                     system: "checkmark.seal.fill", color: .green,
                     filter: .fullyPosted)
            statCard(label: "Partial",      value: "\(partial)",
                     system: "circle.lefthalf.filled", color: .orange,
                     filter: .partial)
            statCard(label: "Not posted",   value: "\(none)",
                     system: "circle", color: .red,
                     filter: .notPosted)
            if scopeless > 0 {
                statCard(label: "No site scope", value: "\(scopeless)",
                         system: "questionmark.circle", color: .secondary,
                         filter: .noScope)
            }
        }
    }

    /// Stat card that doubles as a navigation button — click takes you to the
    /// Clips section with the matching posting-completeness filter pre-applied.
    private func statCard(label: String, value: String, system: String,
                          color: Color, filter: PostingFilter) -> some View {
        Button {
            appState.pendingPostingFilter = filter
            appState.selectedSection = .clips
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: system).font(.title2).foregroundStyle(color)
                    Spacer()
                    Image(systemName: "arrow.right.circle")
                        .font(.callout).foregroundStyle(.tertiary)
                }
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(label).font(.callout).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help("Show \(label.lowercased()) in the Clips list")
    }

    // MARK: - Per-target progress

    private var perTargetProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Per posting target").font(.title3.weight(.semibold))
                Spacer()
                Button {
                    appState.selectedSection = .postingBatch
                } label: {
                    Label("Open Posting Batch", systemImage: "paperplane.fill")
                        .font(.callout)
                }
            }

            let targets = PostingTargets.expanded(appState: appState)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                ForEach(targets) { target in
                    targetProgressCard(target)
                }
            }
        }
    }

    private func targetProgressCard(_ target: PostingTarget) -> some View {
        let clipsInScope = summaries.filter { $0.clip.personaCode == target.personaCode }
        let total = clipsInScope.count
        let posted = clipsInScope.filter { sum in
            guard let sid = target.site.id else { return false }
            return sum.postedSiteIds.contains(sid)
        }.count
        let progress = total > 0 ? Double(posted) / Double(total) : 0

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(personaColor(target.personaCode)).frame(width: 10, height: 10)
                Text(target.label).font(.headline)
                Spacer()
                Text("\(posted) / \(total)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { appState.selectedSection = .postingBatch }
    }

    // MARK: - Clip matrix

    private var clipMatrix: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Clip × site posting status").font(.title3.weight(.semibold))
                Spacer()
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { f in
                        Text(f.label).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }

            Text("Each clip should be posted to every site in its persona's scope. Cells: ✓ posted, • not yet posted.")
                .font(.caption).foregroundStyle(.secondary)

            if filteredSummaries.isEmpty {
                Text("Nothing matches the current filter.")
                    .font(.callout).foregroundStyle(.secondary).padding()
            } else {
                matrixTable
            }
        }
    }

    private var matrixTable: some View {
        VStack(spacing: 0) {
            // Rows
            ForEach(filteredSummaries.prefix(200)) { summary in
                clipRow(summary)
                Divider()
            }

            if filteredSummaries.count > 200 {
                HStack {
                    Spacer()
                    Text("Showing first 200 of \(filteredSummaries.count) clips. Use the Clips list for full search.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator, lineWidth: 1))
    }

    private func clipRow(_ summary: ClipSummary) -> some View {
        HStack(spacing: 12) {
            // Status pill
            statusPill(for: summary)
                .frame(width: 70)

            // Persona dot
            Circle().fill(personaColor(summary.clip.personaCode)).frame(width: 8, height: 8)

            // Title + id
            VStack(alignment: .leading, spacing: 1) {
                Text(summary.clip.title.isEmpty ? "Untitled" : summary.clip.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(summary.clip.title.isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
                Text("\(summary.clip.id)  ·  \(summary.clip.personaCode)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Site indicators
            HStack(spacing: 4) {
                ForEach(summary.scopedSites) { site in
                    siteIndicator(site: site, posted: summary.postedSiteIds.contains(site.id ?? -1))
                }
                if summary.scopedSites.isEmpty {
                    Text("(no sites scoped)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            appState.focusedClipId = summary.clip.id
            appState.selectedSection = .clips
        }
    }

    private func statusPill(for summary: ClipSummary) -> some View {
        let (label, color, system): (String, Color, String) = {
            if summary.totalScoped == 0  { return ("—",        .secondary, "circle.dashed") }
            if summary.isComplete        { return ("done",     .green,     "checkmark.circle.fill") }
            if summary.notPosted         { return ("0/\(summary.totalScoped)", .red, "circle") }
            return ("\(summary.totalPosted)/\(summary.totalScoped)", .orange, "circle.lefthalf.filled")
        }()
        return HStack(spacing: 4) {
            Image(systemName: system)
            Text(label)
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(color)
    }

    private func siteIndicator(site: Site, posted: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: posted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(posted ? .green : Color.tertiaryLabel)
            Text(site.code)
                .font(.caption2.monospaced())
                .foregroundStyle(posted ? .secondary : .tertiary)
        }
        .frame(width: 36)
        .help(posted ? "Posted to \(site.displayName)" : "Not posted to \(site.displayName)")
    }

    // MARK: - Helpers

    private func personaColor(_ code: String) -> Color {
        if let p = appState.persona(forCode: code), let c = Color(hex: p.colorHex) {
            return c
        }
        return .accentColor
    }
}

private extension Color {
    static var tertiaryLabel: Color { Color(NSColor.tertiaryLabelColor) }
}
