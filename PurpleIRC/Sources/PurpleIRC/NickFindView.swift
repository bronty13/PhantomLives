import SwiftUI

/// Dedicated "Find <nick> in logs" sheet (sidebar user-list → right-click →
/// Find …). Surfaces every persisted log line *authored by* the chosen nick
/// or a fuzzy variant of it — `john_doe` also turns up `johndoe1`, `johnny1`,
/// and (when loosened) `jdough1`.
///
/// Powered by `LogStore.searchAuthored(nick:threshold:limit:)`. The fuzziness
/// is tunable live via the slider: drag toward "Looser" to pull in more
/// distant variants, toward "Exact" to keep only near-identical nicks. The
/// chips under the slider show which variant nicks actually matched. Clicking
/// a result jumps to its buffer via the shared `ChatModel.jumpToLogHit`.
struct NickFindView: View {
    @EnvironmentObject var model: ChatModel
    @Environment(\.dismiss) private var dismiss

    let request: ChatModel.NickFindRequest

    /// Match threshold handed to `searchAuthored`. Lower = looser. 0.84 is the
    /// default sweet spot: catches decoration/alt variants (`johndoe1`,
    /// `johnny1`) while keeping precision; drop toward 0.4 to reach distant
    /// variants like `jdough1`.
    @State private var threshold: Double = 0.84
    @State private var hits: [LogStore.SearchHit] = []
    @State private var searching: Bool = false
    @State private var hitLimitReached: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil

    private static let resultLimit = 500

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            fuzzinessBar
            if !matchedVariants.isEmpty {
                variantsBar
            }
            Divider()
            resultsBody
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear { scheduleSearch() }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.text.rectangle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Find “\(request.nick)” in logs")
                    .font(.title3)
                Text("Lines this nick (and fuzzy variants) wrote, across every network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if searching {
                ProgressView().controlSize(.small)
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(14)
    }

    // MARK: - Fuzziness slider

    @ViewBuilder
    private var fuzzinessBar: some View {
        HStack(spacing: 10) {
            Text("Fuzziness")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Looser")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            // Slider runs left→right from loose (0.40) to exact (1.0). We bind
            // the threshold directly; re-search on release (debounced).
            Slider(value: $threshold, in: 0.40...1.0)
                .frame(maxWidth: 320)
                .onChange(of: threshold) { _, _ in scheduleSearch() }
            Text("Exact")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Matched-variant chips

    @ViewBuilder
    private var variantsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("Matched:")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                ForEach(matchedVariants, id: \.self) { nick in
                    Text(nick)
                        .font(.caption)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsBody: some View {
        if hits.isEmpty && !searching {
            ContentUnavailableView(
                "No logged lines",
                systemImage: "questionmark.folder",
                description: Text("No persisted log line was authored by “\(request.nick)” or a variant at this fuzziness. Drag the slider toward “Looser” to widen the match.")
            )
        } else {
            List(hits) { hit in
                resultRow(hit)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { jump(hit) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            footer
        }
    }

    @ViewBuilder
    private var footer: some View {
        if hitLimitReached {
            Text("Showing the first \(Self.resultLimit) matches. Tighten the fuzziness for fewer.")
                .font(.caption).foregroundStyle(.tertiary)
                .padding(.horizontal, 14).padding(.vertical, 6)
        } else if !hits.isEmpty {
            Text("\(hits.count) line\(hits.count == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.tertiary)
                .padding(.horizontal, 14).padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func resultRow(_ hit: LogStore.SearchHit) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(hit.buffer)
                        .font(.system(.body, design: .monospaced))
                    Text("on").foregroundStyle(.tertiary).font(.caption)
                    Text(hit.network).font(.caption).foregroundStyle(.secondary)
                    if let nick = hit.matchedNick,
                       nick.lowercased() != request.nick.lowercased() {
                        // Surface the variant inline when it isn't the exact
                        // nick searched, so the row explains why it matched.
                        Text("· \(nick)")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(stripTimestampPrefix(hit.line))
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                if let ts = hit.timestamp {
                    Text(relative(ts)).font(.caption2).foregroundStyle(.secondary)
                }
                Button("Jump") { jump(hit) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Search

    private func scheduleSearch() {
        searchTask?.cancel()
        searching = true
        let nick = request.nick
        let thresh = threshold
        let store = model.logStore
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            let result = await store.searchAuthored(
                nick: nick, threshold: thresh, limit: Self.resultLimit)
            if Task.isCancelled { return }
            await MainActor.run {
                hits = result
                hitLimitReached = result.count >= Self.resultLimit
                searching = false
            }
        }
    }

    /// Distinct variant nicks present in the current hits, ordered by how
    /// strongly they matched (the hits are already score-sorted).
    private var matchedVariants: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for hit in hits {
            guard let nick = hit.matchedNick else { continue }
            let key = nick.lowercased()
            if seen.insert(key).inserted { out.append(nick) }
        }
        return out
    }

    private func jump(_ hit: LogStore.SearchHit) {
        model.jumpToLogHit(hit)
        dismiss()
    }

    // MARK: - Helpers

    private func stripTimestampPrefix(_ line: String) -> String {
        guard let sp = line.firstIndex(of: " ") else { return line }
        return String(line[line.index(after: sp)...])
    }

    private func relative(_ date: Date) -> String {
        RelativeTime.string(date)
    }
}
