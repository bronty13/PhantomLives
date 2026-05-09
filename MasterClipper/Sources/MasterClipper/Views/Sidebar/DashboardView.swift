import SwiftUI

/// Editorial-style dashboard.
///
/// Layout = 220px meta column (issue eyebrow, headline, deck, persona list,
/// pipeline) + content column (4-cell number strip + 2-col grid of clip×site
/// table and per-target progress).
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
            case .completed:  return "Done"
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
        var notPosted: Bool  { totalPosted == 0 }
        var partial: Bool    { totalPosted > 0 && !isComplete }
    }

    var body: some View {
        HStack(spacing: 0) {
            metaColumn
                .frame(width: 280)
                .frame(maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .trailing) { EdHairline().frame(width: 1) }

            contentColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(EdColor.bone)
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
            .filter { !$0.postingExcluded }
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

    // MARK: - Meta column

    private var metaColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                masthead
                personasInScope
                pipelineList
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
    }

    private var masthead: some View {
        let s = summaries
        let live = s.filter(\.isComplete).count
        let none = s.filter(\.notPosted).count
        let activePersonas = Set(s.map(\.clip.personaCode)).count
        let issueNumber = AppVersion.build.split(separator: ".").first.map(String.init) ?? "—"

        return VStack(alignment: .leading, spacing: 14) {
            EdEyebrow(text: "Issue \(issueNumber) · Production")
            EdHeadline(text: "On the floor today.", emphasized: "today")
            EdDeck(text: deckText(total: s.count, live: live, none: none))
            EdByline(text: "— \(s.count) clips · \(activePersonas) personas active")
        }
    }

    private func deckText(total: Int, live: Int, none: Int) -> String {
        let active = total - live
        if total == 0 {
            return "Catalog is empty. Import a sheet or create a clip to begin."
        }
        if active == 0 {
            return "Every clip in the catalog is fully posted. Nothing needs attention."
        }
        if none > 0 {
            return "\(active) clips in flight. \(live) are live. The \(none) below need a price, a category, or a click."
        }
        return "\(active) clips in flight. \(live) are live. Each is partway through its scope."
    }

    private var personasInScope: some View {
        let counts: [(persona: Persona, count: Int)] = appState.personas
            .filter { !$0.archived }
            .map { p in
                let n = appState.clips.filter { !$0.archived && $0.personaCode == p.code }.count
                return (p, n)
            }
            .sorted { $0.0.sortOrder < $1.0.sortOrder }

        return VStack(alignment: .leading, spacing: 6) {
            EdEyebrow(text: "Personas in scope")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(counts, id: \.persona.id) { row in
                    HStack(spacing: 10) {
                        EdPersonaSwatch(color: appState.color(forPersona: row.persona.code))
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(row.persona.displayName)
                                .font(EdFont.serif(15, weight: .semibold))
                            Text(row.persona.code)
                                .font(EdFont.mono(10.5))
                                .foregroundStyle(EdColor.ink(0.5))
                        }
                        Spacer()
                        Text(String(format: "%02d clips", row.count))
                            .font(EdFont.mono(11))
                            .foregroundStyle(EdColor.ink(0.65))
                    }
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .strokeBorder(style: .init(lineWidth: 1, dash: [1, 2]))
                            .foregroundStyle(EdColor.ink(0.18))
                            .frame(height: 1)
                    }
                }
            }
        }
    }

    private var pipelineList: some View {
        let s = summaries
        let counts: [(label: String, n: Int, bold: Bool)] = [
            ("New",      appState.clips.filter { !$0.archived && $0.statusEnum == .new }.count,        false),
            ("Editing",  appState.clips.filter { !$0.archived && $0.statusEnum == .editing }.count,    false),
            ("To post",  appState.clips.filter { !$0.archived && $0.statusEnum == .toPost }.count,     false),
            ("Posting",  appState.clips.filter { !$0.archived && $0.statusEnum == .posting }.count,    false),
            ("Live",     s.filter(\.isComplete).count,                                                  true),
        ]
        return VStack(alignment: .leading, spacing: 6) {
            EdEyebrow(text: "Pipeline · auto-derived")
            ForEach(Array(counts.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.label)
                        .font(EdFont.sans(12.5, weight: row.bold ? .semibold : .regular))
                    Spacer()
                    Text(String(format: "%02d", row.n))
                        .font(EdFont.mono(11, weight: row.bold ? .semibold : .regular))
                        .foregroundStyle(EdColor.ink(0.65))
                }
                .padding(.vertical, 3)
            }
        }
    }

    // MARK: - Content column

    private var contentColumn: some View {
        VStack(spacing: 0) {
            numStrip
            HStack(spacing: 0) {
                clipMatrixPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                EdHairline().frame(width: 1)
                targetsPanel
                    .frame(width: 380)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - Number strip

    private var numStrip: some View {
        let s = summaries
        let total = s.count
        let fully = s.filter(\.isComplete).count
        let partial = s.filter(\.partial).count
        let none = s.filter(\.notPosted).count
        let pct = total > 0 ? Int((Double(fully) / Double(total)) * 100) : 0

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                statButton(label: "Total clips", value: total,
                           hint: "across \(appState.personas.filter { !$0.archived }.count) personas",
                           accent: false, filter: .all, divider: true)
                statButton(label: "Fully posted", value: fully,
                           hint: "\(pct)% of catalog",
                           accent: true, filter: .fullyPosted, divider: true)
                statButton(label: "Partial", value: partial,
                           hint: "need a few more sites",
                           accent: false, filter: .partial, divider: true)
                statButton(label: "Not posted", value: none,
                           hint: "price/category missing",
                           accent: false, filter: .notPosted, divider: false)
            }
            EdHairline()
        }
    }

    private func statButton(label: String, value: Int, hint: String, accent: Bool,
                            filter: PostingFilter, divider: Bool) -> some View {
        Button {
            appState.pendingPostingFilter = filter
            appState.selectedSection = .clips
        } label: {
            EdNumberCell(label: label, figure: "\(value)", hint: hint, accent: accent)
                .overlay(alignment: .trailing) {
                    if divider { Rectangle().fill(EdColor.ink(0.18)).frame(width: 1) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show \(label.lowercased()) in the Clips list")
    }

    // MARK: - Clip × site panel

    private var clipMatrixPanel: some View {
        VStack(spacing: 0) {
            EdSectionHeading(title: "Clip × site",
                             trailing: filterTrailingLabel)
            tableHeader
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    ForEach(filteredSummaries.prefix(200)) { summary in
                        clipRow(summary)
                        Rectangle().fill(EdColor.ink(0.1)).frame(height: 1)
                    }
                    if filteredSummaries.count > 200 {
                        Text("Showing first 200 of \(filteredSummaries.count). Use Clips list for full search.")
                            .font(EdFont.mono(10.5))
                            .foregroundStyle(EdColor.ink(0.55))
                            .padding(.vertical, 12)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            tableFooter
        }
    }

    private var filterTrailingLabel: String {
        let visible = filteredSummaries.count
        let total = summaries.count
        return "\(filter.label) · \(visible) / \(total)"
    }

    private var tableHeader: some View {
        let cols: [GridItem] = [
            GridItem(.fixed(28), alignment: .leading),
            GridItem(.flexible(), alignment: .leading),
            GridItem(.fixed(96), alignment: .leading),
            GridItem(.fixed(110), alignment: .leading),
            GridItem(.fixed(140), alignment: .leading),
        ]
        return VStack(spacing: 0) {
            LazyVGrid(columns: cols, alignment: .leading, spacing: 0) {
                ForEach(["#", "Title", "Persona", "Status", "Sites"], id: \.self) { h in
                    Text(h.uppercased())
                        .font(EdFont.mono(10))
                        .tracking(1.2)
                        .foregroundStyle(EdColor.ink(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            EdHairline()
        }
    }

    private func clipRow(_ summary: ClipSummary) -> some View {
        let cols: [GridItem] = [
            GridItem(.fixed(28), alignment: .leading),
            GridItem(.flexible(), alignment: .leading),
            GridItem(.fixed(96), alignment: .leading),
            GridItem(.fixed(110), alignment: .leading),
            GridItem(.fixed(140), alignment: .leading),
        ]
        let idx = (filteredSummaries.firstIndex(where: { $0.id == summary.id }) ?? 0) + 1
        return Button {
            appState.focusedClipId = summary.clip.id
            appState.selectedSection = .clips
        } label: {
            LazyVGrid(columns: cols, alignment: .leading, spacing: 0) {
                Text(String(format: "%02d", idx))
                    .font(EdFont.mono(10))
                    .foregroundStyle(EdColor.ink(0.45))

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.clip.title.isEmpty ? "Untitled" : summary.clip.title)
                        .font(EdFont.serif(16, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(summary.clip.title.isEmpty ? EdColor.ink(0.45) : EdColor.ink)
                    HStack(spacing: 6) {
                        Text(summary.clip.id)
                            .font(EdFont.mono(10.5))
                            .foregroundStyle(EdColor.ink(0.55))
                        if let len = summary.clip.lengthSeconds {
                            Text("·")
                                .font(EdFont.mono(10.5))
                                .foregroundStyle(EdColor.ink(0.4))
                            Text(formatLength(len))
                                .font(EdFont.mono(10.5))
                                .foregroundStyle(EdColor.ink(0.55))
                        }
                    }
                }

                HStack(spacing: 6) {
                    EdPersonaSwatch(color: appState.color(forPersona: summary.clip.personaCode), size: 9)
                    Text(summary.clip.personaCode)
                        .font(EdFont.mono(11, weight: .semibold))
                        .tracking(0.66)
                }

                EdStatusPill(status: edStatus(for: summary))
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    if summary.scopedSites.isEmpty {
                        Text("(no scope)")
                            .font(EdFont.mono(10))
                            .foregroundStyle(EdColor.ink(0.4))
                    } else {
                        ForEach(summary.scopedSites) { site in
                            EdSiteCell(code: site.code,
                                       posted: summary.postedSiteIds.contains(site.id ?? -1))
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func edStatus(for summary: ClipSummary) -> EdStatus {
        if summary.isComplete { return .live }
        switch summary.clip.statusEnum {
        case .posting:    return .posting
        case .toPost:     return .toPost
        case .editing:    return .editing
        case .new:        return .new
        case .production: return summary.isComplete ? .live : .posting
        case .archived:   return .offline
        }
    }

    private var tableFooter: some View {
        VStack(spacing: 0) {
            EdHairline(color: EdColor.ink(0.12))
            HStack {
                Text("SHOWING \(min(filteredSummaries.count, 200)) / \(summaries.count)")
                    .font(EdFont.mono(10.5))
                    .foregroundStyle(EdColor.ink(0.55))
                Spacer()
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { f in
                        Text(f.label).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
                Button {
                    appState.selectedSection = .clips
                } label: {
                    Text("OPEN CLIPS LIST →")
                }
                .buttonStyle(EdAcidPillButtonStyle())
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
        }
    }

    private func formatLength(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Targets panel

    private var targetsPanel: some View {
        VStack(spacing: 0) {
            EdSectionHeading(title: "Per posting target", trailing: "Open Batch ↗")
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    let targets = PostingTargets.expanded(appState: appState)
                    let withProgress = targets.map { t -> (PostingTarget, Int, Int, Double) in
                        let inScope = summaries.filter { $0.clip.personaCode == t.personaCode }
                        let total = inScope.count
                        let posted: Int = {
                            guard let sid = t.site.id else { return 0 }
                            return inScope.filter { $0.postedSiteIds.contains(sid) }.count
                        }()
                        let pct = total > 0 ? Double(posted) / Double(total) : 0
                        return (t, posted, total, pct)
                    }

                    let mostBehindIdx = withProgress.enumerated().min(by: {
                        ($0.element.3, -$0.element.2) < ($1.element.3, -$1.element.2)
                    })?.offset

                    ForEach(Array(withProgress.enumerated()), id: \.offset) { (i, row) in
                        targetRow(row.0, posted: row.1, total: row.2, pct: row.3,
                                  accent: i == mostBehindIdx)
                        EdHairline(color: EdColor.ink(0.12))
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button {
                    appState.selectedSection = .postingBatch
                } label: {
                    Text("OPEN POSTING BATCH →")
                }
                .buttonStyle(EdAcidPillButtonStyle())
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .overlay(alignment: .top) { EdHairline(color: EdColor.ink(0.12)) }
        }
    }

    private func targetRow(_ target: PostingTarget, posted: Int, total: Int,
                           pct: Double, accent: Bool) -> some View {
        Button {
            appState.selectedSection = .postingBatch
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        EdPersonaSwatch(color: appState.color(forPersona: target.personaCode), size: 10)
                        Text(personaName(target.personaCode))
                            .font(EdFont.serif(17, weight: .semibold))
                        Text("→ \(target.site.displayName)")
                            .font(EdFont.mono(10.5))
                            .tracking(0.84)
                            .foregroundStyle(EdColor.ink(0.55))
                    }
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(posted)")
                            .font(EdFont.mono(14, weight: .semibold))
                        Text("/\(total)")
                            .font(EdFont.mono(14))
                            .foregroundStyle(EdColor.ink(0.5))
                    }
                }
                ZStack(alignment: .leading) {
                    Rectangle().fill(EdColor.ink(0.06))
                    Rectangle().fill(accent ? EdColor.acid : EdColor.ink)
                        .frame(width: max(2, CGFloat(pct) * 320))
                }
                .frame(height: 14)
                .overlay(Rectangle().strokeBorder(EdColor.ink, lineWidth: 1))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func personaName(_ code: String) -> String {
        appState.persona(forCode: code)?.displayName ?? code
    }
}
