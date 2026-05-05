import SwiftUI

/// Drill-down posting wizard:
/// 1. **Targets** — grid of (site, persona) cards. Each card shows pending count.
/// 2. **Queue** — list of clips that need posting for the chosen target. Click
///    a clip to open the detail, or "Start posting" to take the first one.
/// 3. **Posting** — embedded clip detail with per-field copy buttons. "Next"
///    advances through the queue; when the queue empties, falls back to the
///    queue stage. From there a button returns to the site list.
///
/// Breadcrumbs at top let the user jump back to any earlier stage.
struct PostingBatchView: View {
    @EnvironmentObject private var appState: AppState

    enum Stage { case targets, queue, posting }

    @State private var stage: Stage = .targets
    @State private var selectedTarget: PostingTarget?
    @State private var pendingClips: [Clip] = []
    @State private var currentClip: Clip?
    @State private var batchStartCount: Int = 0
    @State private var pendingCounts: [String: Int] = [:]
    @State private var loadError: String?
    @State private var showingQueueList: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbs
            Divider()
            stageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Posting Batch")
        .onAppear { reloadCounts() }
        .onChange(of: appState.clips.count) { _, _ in reloadCounts() }
        .sheet(isPresented: $showingQueueList) {
            if let target = selectedTarget {
                PostingQueueListSheet(target: target, clips: pendingClips)
            }
        }
    }

    // MARK: - Breadcrumbs

    private var breadcrumbs: some View {
        HStack(spacing: 8) {
            crumb("Sites", isCurrent: stage == .targets) {
                stage = .targets
                selectedTarget = nil
                pendingClips = []
                currentClip = nil
                reloadCounts()
            }

            if let target = selectedTarget, stage != .targets {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary).font(.caption)
                crumb(target.label, isCurrent: stage == .queue) {
                    stage = .queue
                    currentClip = nil
                }
            }

            if let clip = currentClip, stage == .posting {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary).font(.callout)
                Text(clip.title.isEmpty ? "Untitled" : clip.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Right-side status. Position in the batch = clips already
            // marked posted (= batchStartCount - pending) PLUS the
            // current clip's offset inside the still-pending list (so
            // skipping a clip — which doesn't remove it — bumps the
            // counter forward correctly).
            if stage == .queue {
                Text("\(pendingClips.count) of \(batchStartCount) remaining")
                    .font(.callout).foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if stage == .posting,
                      let clip = currentClip {
                let posted = batchStartCount - pendingClips.count
                let idxInPending = pendingClips.firstIndex(where: { $0.id == clip.id }) ?? 0
                let position = posted + idxInPending + 1
                Text("Clip \(position) of \(batchStartCount)")
                    .font(.callout).foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // Show-queue button — surfaces the full pending list so
            // the user can see / copy IDs / titles / filenames in
            // order for sites that allow bulk-uploading multiple
            // clips at once. Only visible when there's a queue to show.
            if (stage == .queue || stage == .posting),
               selectedTarget != nil,
               !pendingClips.isEmpty {
                Button {
                    showingQueueList = true
                } label: {
                    Label("Show queue list", systemImage: "list.number")
                }
                .help("Open a list of every pending clip in this batch — IDs, titles, and production filenames, all click-to-copy.")
            }
        }
        .padding(14)
        .background(.background.secondary)
    }

    @ViewBuilder
    private func crumb(_ text: String, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        if isCurrent {
            Text(text).font(.headline)
        } else {
            Button(action: action) {
                Text(text).font(.body).foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Stage router

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .targets:
            targetsView
        case .queue:
            if let target = selectedTarget { queueView(for: target) }
            else { targetsView }
        case .posting:
            if let target = selectedTarget, let clip = currentClip {
                PostingClipWindow(
                    clip: clip,
                    target: target,
                    onMarkPosted: { markPosted($0) },
                    onClose: { stage = .queue; currentClip = nil },
                    onAdvance: { advanceAfter($0) }
                )
                // Per-clip identity — without this, SwiftUI reuses the
                // window's @State (priceDraft, notes, etc.) across
                // clips, so advancing carries over the previous clip's
                // values instead of seeding from the new one.
                .id(clip.id)
            } else if let target = selectedTarget {
                queueView(for: target)
            } else {
                targetsView
            }
        }
    }

    // MARK: - Stage 1: Targets

    private var targetsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pick a posting target")
                    .font(.title2.weight(.semibold))
                Text("Each (site, persona) pair runs as its own batch — Clips4Sale [CoC] and Clips4Sale [PoA] use different logins, so they're separate.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: 720, alignment: .leading)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 14)], spacing: 14) {
                    ForEach(PostingTargets.expanded(appState: appState)) { target in
                        targetCard(target)
                    }
                }
            }
            .padding(20)
        }
    }

    private func targetCard(_ target: PostingTarget) -> some View {
        let count = pendingCounts[target.id] ?? 0
        let allDone = count == 0

        return Button {
            selectedTarget = target
            loadQueue(for: target)
            stage = .queue
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle().fill(personaColor(target.personaCode)).frame(width: 12, height: 12)
                    Text(target.site.code).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Spacer()
                    Text(target.personaCode)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(personaColor(target.personaCode).opacity(0.25), in: Capsule())
                }
                Text(target.site.displayName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                HStack {
                    if allDone {
                        Label("All posted", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green).font(.caption)
                    } else {
                        Text("\(count) clip\(count == 1 ? "" : "s") to post")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stage 2: Queue

    private func queueView(for target: PostingTarget) -> some View {
        VStack(spacing: 0) {
            queueHeader(for: target)
            Divider()
            queueBody(for: target)
        }
    }

    private func queueHeader(for target: PostingTarget) -> some View {
        let total = batchStartCount
        let remaining = pendingClips.count
        let done = max(0, total - remaining)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(target.label).font(.title2.weight(.semibold))
                    Text("Track-only — open a clip to copy fields into the upload form, then mark posted.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if !pendingClips.isEmpty {
                    Button {
                        currentClip = pendingClips.first
                        stage = .posting
                    } label: {
                        Label("Start posting", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
        }
        .padding(16)
    }

    @ViewBuilder
    private func queueBody(for target: PostingTarget) -> some View {
        if let error = loadError {
            Text(error).foregroundStyle(.red).padding()
        } else if pendingClips.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.green)
                Text("All clips posted to \(target.label).")
                    .font(.headline)
                HStack {
                    if let next = nextTargetAfterCurrent() {
                        Button("Next batch (\(next.label))") {
                            selectedTarget = next
                            loadQueue(for: next)
                            stage = .queue
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("Back to sites") {
                        stage = .targets
                        selectedTarget = nil
                        pendingClips = []
                        reloadCounts()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(pendingClips) { clip in
                    queueRow(clip, target: target)
                }
            }
            .listStyle(.inset)
        }
    }

    private func queueRow(_ clip: Clip, target: PostingTarget) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(clip.title.isEmpty ? "Untitled" : clip.title).font(.headline)
                    Text("[\(clip.personaCode)]")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    ClipIDLabel(id: clip.id, style: .captionSecondary)
                    if let date = clip.goLiveDate, !date.isEmpty {
                        Label(date, systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
                    }
                    if let secs = clip.lengthSeconds {
                        Label(DurationFormatter.format(secs), systemImage: "clock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Button("Open") {
                currentClip = clip
                stage = .posting
            }
            .buttonStyle(.borderedProminent)
            Button("Skip") {
                pendingClips.removeAll { $0.id == clip.id }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Mutations

    private func loadQueue(for target: PostingTarget) {
        guard let siteId = target.site.id else {
            pendingClips = []
            batchStartCount = 0
            return
        }
        do {
            pendingClips = try PostingService.clipsNotPosted(
                toSiteId: siteId,
                personaScope: [target.personaCode]
            )
            batchStartCount = pendingClips.count
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func reloadCounts() {
        var counts: [String: Int] = [:]
        for target in PostingTargets.expanded(appState: appState) {
            guard let siteId = target.site.id else { continue }
            let clips = (try? PostingService.clipsNotPosted(
                toSiteId: siteId,
                personaScope: [target.personaCode]
            )) ?? []
            counts[target.id] = clips.count
        }
        pendingCounts = counts
    }

    private func markPosted(_ clip: Clip) {
        guard let target = selectedTarget, let siteId = target.site.id else { return }
        do {
            try PostingService.markPosted(clipId: clip.id, siteId: siteId)
            pendingClips.removeAll { $0.id == clip.id }
            // Pipeline status auto-recomputed by upsertPosting → refresh.
            appState.reloadClips()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func advanceAfter(_ clip: Clip) {
        // Two paths land here:
        //   • Mark posted / Posted & next — `markPosted` already
        //     removed the clip from pendingClips, so the next clip is
        //     just `pendingClips.first`.
        //   • Skip for now — clip is STILL in pendingClips at some
        //     index; we want the one after it.
        let nextClip: Clip? = {
            if let curIdx = pendingClips.firstIndex(where: { $0.id == clip.id }) {
                // Skip path: still in the list — pick the next entry.
                let nextIdx = curIdx + 1
                return nextIdx < pendingClips.count ? pendingClips[nextIdx] : nil
            }
            // Mark-posted path: clip already gone — first remaining is next.
            return pendingClips.first
        }()
        if let next = nextClip {
            currentClip = next
        } else {
            // Queue is empty (or the user skipped the last clip) —
            // fall back to the queue stage so the user sees the
            // "all done" empty state and can move to the next target.
            currentClip = nil
            stage = .queue
            reloadCounts()
        }
    }

    private func nextTargetAfterCurrent() -> PostingTarget? {
        let all = PostingTargets.expanded(appState: appState)
        guard let current = selectedTarget,
              let idx = all.firstIndex(where: { $0.id == current.id }) else { return nil }
        return idx + 1 < all.count ? all[idx + 1] : nil
    }

    // MARK: - Helpers

    private func personaColor(_ code: String) -> Color {
        if let p = appState.persona(forCode: code), let c = Color(hex: p.colorHex) {
            return c
        }
        return .accentColor
    }
}
