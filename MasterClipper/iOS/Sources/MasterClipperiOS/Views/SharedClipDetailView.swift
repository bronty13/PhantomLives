import SwiftUI
import MasterClipperCore

/// Detail view for a SharedClipRow. Read-only for now (Phase 6d v1).
/// Read-write recipients will get edit affordances in a follow-up that
/// also wires the macOS side to reconcile changes back into SQLite.
struct SharedClipDetailView: View {
    let target: SharedClipNavTarget
    @EnvironmentObject private var appState: iOSAppState

    var body: some View {
        ScrollView {
            if let session = appState.sharedReader.sessions.first(where: { $0.id == target.sessionId }),
               let clip = session.clips.first(where: { $0.id == target.clipId }) {
                VStack(alignment: .leading, spacing: 16) {
                    header(clip: clip, session: session)
                    if !clip.descriptionRefined.isEmpty || !clip.descriptionRaw.isEmpty {
                        section("Description") {
                            Text(clip.descriptionRefined.isEmpty ? clip.descriptionRaw : clip.descriptionRefined)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }
                    detailsSection(clip: clip)
                    postingsSection(clip: clip)
                    notesSection(clip: clip)
                }
                .padding()
            } else {
                Text("Clip not available")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .navigationTitle("Shared clip")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(clip: SharedClipRow, session: SharedShareSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            thumbnail(clip: clip)
                .aspectRatio(16/9, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(clip.title.isEmpty ? clip.id : clip.title)
                .font(.title2.bold())

            HStack(spacing: 8) {
                Text(clip.personaCode)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.gray.opacity(0.2), in: Capsule())
                Label(clip.statusEnum.label, systemImage: clip.statusEnum.systemImage)
                    .font(.caption)
                Spacer()
                if !session.canEdit {
                    Label("View only", systemImage: "eye")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(clip.id)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func thumbnail(clip: SharedClipRow) -> some View {
        if let url = clip.thumbnailLocalURL,
           FileManager.default.fileExists(atPath: url.path),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                Color.gray.opacity(0.12)
                Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary)
            }
        }
    }

    private func detailsSection(clip: SharedClipRow) -> some View {
        section("Details") {
            VStack(alignment: .leading, spacing: 6) {
                if let d = clip.contentDate { row("Content date", d) }
                if let g = clip.goLiveDate  { row("Go-live date", g) }
                if let l = clip.lengthSeconds { row("Length", formatLength(l)) }
                if let p = clip.priceCents {
                    row("Price", String(format: "$%.2f", Double(p) / 100.0))
                }
                if clip.salesCount > 0 { row("Sales", "\(clip.salesCount)") }
                if !clip.keywords.isEmpty { row("Keywords", clip.keywords) }
                if !clip.performers.isEmpty { row("Performers", clip.performers) }
            }
        }
    }

    @ViewBuilder
    private func postingsSection(clip: SharedClipRow) -> some View {
        if !clip.postings.isEmpty {
            section("Postings") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(clip.postings, id: \.self) { p in
                        HStack {
                            Text("Site #\(p.siteId)").font(.body.weight(.medium))
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

    @ViewBuilder
    private func notesSection(clip: SharedClipRow) -> some View {
        if !clip.notes.isEmpty {
            section("Notes") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(clip.notes) { note in
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

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).textSelection(.enabled)
        }
        .font(.callout)
    }

    private func formatLength(_ s: Int) -> String {
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .tracking(0.5)
            content()
        }
    }
}
