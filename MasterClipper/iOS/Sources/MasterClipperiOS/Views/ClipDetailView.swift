import SwiftUI
import MasterClipperCore

struct ClipDetailView: View {
    let clipId: String
    @EnvironmentObject private var appState: iOSAppState

    var body: some View {
        ScrollView {
            if let clip = appState.clips.first(where: { $0.id == clipId }) {
                VStack(alignment: .leading, spacing: 16) {
                    header(clip: clip)
                    descriptionSection(clip: clip)
                    metaSection(clip: clip)
                    categoriesSection
                    postingsSection
                    notesSection
                    if !clip.transcript.isEmpty {
                        transcriptSection(clip: clip)
                    }
                }
                .padding()
            } else {
                Text("Clip not found")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .navigationTitle("Clip")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(clip: Clip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ThumbnailView(clipId: clip.id)
                .aspectRatio(16/9, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(clip.title.isEmpty ? clip.id : clip.title)
                .font(.title2.bold())

            HStack(spacing: 8) {
                if let p = appState.persona(code: clip.personaCode) {
                    PersonaBadge(persona: p)
                }
                StatusBadge(status: clip.statusEnum)
                if clip.archived {
                    Label("Archived", systemImage: "archivebox")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(clip.id)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func descriptionSection(clip: Clip) -> some View {
        if !clip.descriptionRefined.isEmpty || !clip.descriptionRaw.isEmpty {
            Section_(title: "Description") {
                if !clip.descriptionRefined.isEmpty {
                    Text(clip.descriptionRefined)
                        .font(.body)
                        .textSelection(.enabled)
                } else {
                    Text(clip.descriptionRaw)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func metaSection(clip: Clip) -> some View {
        Section_(title: "Details") {
            VStack(alignment: .leading, spacing: 6) {
                if let date = clip.contentDate { detailRow("Content date", date) }
                if let goLive = clip.goLiveDate { detailRow("Go-live date", goLive) }
                if let len = clip.lengthSeconds { detailRow("Length", formatDuration(len)) }
                if let cents = clip.priceCents {
                    detailRow("Price", String(format: "$%.2f", Double(cents) / 100.0))
                }
                if clip.salesCount > 0 { detailRow("Sales", "\(clip.salesCount)") }
                if clip.incomeCents > 0 {
                    detailRow("Income", String(format: "$%.2f", Double(clip.incomeCents) / 100.0))
                }
                if !clip.keywords.isEmpty { detailRow("Keywords", clip.keywords) }
                if !clip.performers.isEmpty { detailRow("Performers", clip.performers) }
                if clip.postingExcluded {
                    detailRow("Posting", "Excluded\(clip.exclusionReason.isEmpty ? "" : " — \(clip.exclusionReason)")")
                }
                // Mac-local file paths (fcpProjectFolder, productionFolder,
                // clipFilename) are intentionally hidden on iOS — iOS can't
                // resolve them.
            }
        }
    }

    private var categoriesSection: some View {
        let cats = appState.categories(forClip: clipId)
        return Group {
            if !cats.isEmpty {
                Section_(title: "Categories") {
                    FlowLayout(spacing: 6) {
                        ForEach(cats) { cat in
                            Text(cat.name)
                                .font(.caption.bold())
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(.gray.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private var postingsSection: some View {
        let postings = appState.postings(forClip: clipId)
        return Group {
            if !postings.isEmpty {
                Section_(title: "Postings") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(postings, id: \.self) { p in
                            HStack {
                                if let site = appState.site(id: p.siteId) {
                                    Text(site.code).font(.body.weight(.medium))
                                } else {
                                    Text("Site #\(p.siteId)").font(.body)
                                }
                                Spacer()
                                if p.isPosted, let date = p.postedDate {
                                    Label(date, systemImage: "checkmark.seal.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                } else {
                                    Text(p.statusEnum.rawValue.capitalized)
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        let notes = appState.notes(forClip: clipId)
        return Group {
            if !notes.isEmpty {
                Section_(title: "Notes") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(notes) { note in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(note.operatorName).font(.caption.bold())
                                    Spacer()
                                    Text(note.createdAt).font(.caption2).foregroundStyle(.tertiary)
                                }
                                Text(note.body).font(.body).textSelection(.enabled)
                            }
                            .padding(8)
                            .background(.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
        }
    }

    private func transcriptSection(clip: Clip) -> some View {
        Section_(title: "Transcript") {
            Text(clip.transcript)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).textSelection(.enabled)
        }
        .font(.callout)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct Section_<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .tracking(0.5)
            content()
        }
    }
}

/// Tiny flow layout for category chips. Avoids pulling in a 3rd-party Layout.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
