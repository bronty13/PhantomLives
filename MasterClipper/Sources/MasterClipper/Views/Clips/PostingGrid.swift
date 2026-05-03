import SwiftUI

/// Grid of (site × posted toggle) for a single clip. Sites are filtered to those
/// scoped to the clip's persona. Tapping a checkbox upserts a `clip_postings` row.
struct PostingGrid: View {
    @EnvironmentObject private var appState: AppState
    let clipId: String
    let personaCode: String

    @State private var postings: [Int64: ClipPosting] = [:]
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(scopedSites) { site in
                let p = posting(for: site)
                HStack(spacing: 10) {
                    Toggle(isOn: Binding(
                        get: { p?.statusEnum == .posted },
                        set: { newVal in toggle(site: site, to: newVal) }
                    )) {
                        EmptyView()
                    }
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                    Text(site.displayName)
                        .frame(width: 130, alignment: .leading)

                    Text(site.code)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .leading)

                    if let posted = p?.postedDate, !posted.isEmpty {
                        Text("posted \(posted)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("not posted")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            if scopedSites.isEmpty {
                Text("No sites are scoped to persona \(personaCode). Edit site scope in Settings → Sites.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let loadError {
                Text(loadError).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear(perform: load)
        .onChange(of: clipId) { _, _ in load() }
    }

    private var scopedSites: [Site] {
        appState.sites
            .filter { !$0.archived }
            .filter { $0.appliesTo(personaCode: personaCode) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func posting(for site: Site) -> ClipPosting? {
        guard let sid = site.id else { return nil }
        return postings[sid]
    }

    private func load() {
        do {
            let rows = try DatabaseService.shared.fetchPostings(forClip: clipId)
            postings = Dictionary(uniqueKeysWithValues: rows.map { ($0.siteId, $0) })
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func toggle(site: Site, to posted: Bool) {
        guard let sid = site.id else { return }
        let now = DatabaseService.isoNow()
        let existing = postings[sid]
        let newRow = ClipPosting(
            clipId: clipId,
            siteId: sid,
            postedDate: posted ? DatabaseService.isoDate(Date()) : nil,
            status: posted ? PostingStatus.posted.rawValue : PostingStatus.pending.rawValue,
            notes: existing?.notes ?? "",
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        do {
            try DatabaseService.shared.upsertPosting(newRow)
            postings[sid] = newRow
            // Posting state changed → clip's pipeline status auto-recomputed.
            // Refresh the AppState slice so list/dashboard badges update.
            appState.reloadClips()
        } catch {
            loadError = error.localizedDescription
        }
    }
}
