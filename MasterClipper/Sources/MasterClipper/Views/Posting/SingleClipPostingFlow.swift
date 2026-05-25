import SwiftUI
import MasterClipperCore

/// Single-clip posting flow. Pick a scoped site, then run the regular
/// `PostingClipWindow` against that (clip, site) pair. "Posted & next"
/// cycles to the next un-posted scoped site for the same clip; when the
/// clip is fully posted, the sheet closes.
///
/// Entry points: POST button in `ClipActionsBar`, per-row Post button in
/// `PostingGrid`, and "Post this clip…" context-menu items on the clip
/// tables (Clips, Editing Queue, Posting Queue). The PostingGrid path
/// passes `preselectedSiteId` so the picker is skipped.
struct SingleClipPostingFlow: View {
    @EnvironmentObject private var appState: AppState
    let clip: Clip
    var preselectedSiteId: Int64? = nil
    let onClose: () -> Void

    enum Stage { case picker, posting }

    @State private var stage: Stage = .picker
    @State private var currentTarget: PostingTarget?
    @State private var postedSiteIds: Set<Int64> = []
    @State private var didApplyPreselection = false

    var body: some View {
        Group {
            switch stage {
            case .picker:
                pickerView
            case .posting:
                if let target = currentTarget {
                    PostingClipWindow(
                        clip: liveClip,
                        target: target,
                        onMarkPosted: { _ in markPosted(target: target) },
                        onClose: { backToPicker() },
                        onAdvance: { _ in advanceToNextSite() }
                    )
                    // Reset window @State (notes, priceDraft, categories)
                    // when the target changes — switching sites mid-flow
                    // should land on a fresh form. PostingClipWindow only
                    // watches clip.id, which doesn't change here.
                    .id(target.id)
                } else {
                    pickerView   // defensive — shouldn't be reachable
                }
            }
        }
        .frame(minWidth: 720, idealWidth: 880, minHeight: 580, idealHeight: 760)
        .onAppear { initialLoad() }
    }

    // MARK: - Picker

    private var pickerView: some View {
        VStack(alignment: .leading, spacing: 0) {
            pickerHeader
            Divider()
            pickerBody
            Divider()
            pickerFooter
        }
    }

    private var pickerHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Post this clip to…").font(.title2.weight(.semibold))
                HStack(spacing: 6) {
                    PersonaPill(code: clip.personaCode)
                    Text(clip.title.isEmpty ? "Untitled" : clip.title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Button("Close", action: onClose)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(16)
    }

    @ViewBuilder
    private var pickerBody: some View {
        if scopedSites.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "questionmark.folder")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No sites are scoped to persona \(clip.personaCode).")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Edit site scope in Settings → Sites.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        } else {
            List {
                ForEach(scopedSites) { site in
                    siteRow(site)
                }
            }
            .listStyle(.inset)
        }
    }

    private func siteRow(_ site: Site) -> some View {
        let posted = postedSiteIds.contains(site.id ?? -1)
        return Button {
            openPostingWindow(for: site)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: posted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(posted ? .green : Color(NSColor.tertiaryLabelColor))
                VStack(alignment: .leading, spacing: 1) {
                    Text(site.displayName).font(.body.weight(.medium))
                    Text(site.code)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(posted ? "posted" : "pending")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(posted ? .green : .secondary)
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .help(posted
              ? "Already marked posted on \(site.displayName). Click to update / re-post."
              : "Open the posting window for \(site.displayName).")
    }

    private var pickerFooter: some View {
        HStack {
            let total = scopedSites.count
            let done  = scopedSites.filter { postedSiteIds.contains($0.id ?? -1) }.count
            let remaining = total - done
            if total == 0 {
                EmptyView()
            } else if remaining == 0 {
                Label("All \(total) scoped site\(total == 1 ? "" : "s") posted",
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Text("\(remaining) of \(total) site\(total == 1 ? "" : "s") to post")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.background.secondary)
    }

    // MARK: - State transitions

    private func initialLoad() {
        refreshPostedSet()
        // Skip the picker if a preselected site was supplied (PostingGrid
        // per-row entry). Guard with a flag so the auto-jump only ever
        // fires once per appearance — otherwise returning from the
        // posting stage to the picker would immediately bounce back.
        guard !didApplyPreselection else { return }
        didApplyPreselection = true
        if let preId = preselectedSiteId,
           let site = scopedSites.first(where: { $0.id == preId }) {
            openPostingWindow(for: site)
        }
    }

    private func openPostingWindow(for site: Site) {
        currentTarget = PostingTarget(site: site, personaCode: clip.personaCode)
        stage = .posting
    }

    private func backToPicker() {
        currentTarget = nil
        refreshPostedSet()
        stage = .picker
    }

    private func markPosted(target: PostingTarget) {
        guard let sid = target.site.id else { return }
        do {
            try PostingService.markPosted(clipId: clip.id, siteId: sid)
            postedSiteIds.insert(sid)
            appState.reloadClips()
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func advanceToNextSite() {
        refreshPostedSet()
        // Walk sites in display order, picking the first one not yet
        // posted AND not the current one (so a "Skip for now" tap on the
        // last un-posted site falls through to closing the sheet rather
        // than re-opening the same target).
        let currentId = currentTarget?.site.id
        let next = scopedSites.first { site in
            guard let sid = site.id else { return false }
            if sid == currentId { return false }
            return !postedSiteIds.contains(sid)
        }
        if let next {
            openPostingWindow(for: next)
        } else {
            onClose()
        }
    }

    // MARK: - Data

    private var scopedSites: [Site] {
        appState.sites
            .filter { !$0.archived }
            .filter { $0.appliesTo(personaCode: clip.personaCode) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Always hand `PostingClipWindow` the latest copy of the clip from
    /// AppState — the user can edit price / categories from the dialog,
    /// and we want any change made during the previous site to be visible
    /// when we cycle into the next.
    private var liveClip: Clip {
        appState.clips.first(where: { $0.id == clip.id }) ?? clip
    }

    private func refreshPostedSet() {
        let rows = (try? DatabaseService.shared.fetchPostings(forClip: clip.id)) ?? []
        postedSiteIds = Set(rows.filter { $0.statusEnum == .posted }.map { $0.siteId })
    }
}
