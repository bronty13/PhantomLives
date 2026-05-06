import SwiftUI
import AppKit

/// Sheet for the one-shot "backfill historical categories" operation.
/// Shows the four buckets the planner produced, lets the user check /
/// uncheck individual rows, then commits the user-confirmed subset
/// inside a single DB transaction.
struct HistoricalCategoryBackfillSheet: View {
    @EnvironmentObject private var appState: AppState

    /// Called with the number of clips that received categories on
    /// success, `nil` on cancel.
    let onComplete: (Int?) -> Void

    @State private var plan: HistoricalCategoryBackfillService.Plan? = nil
    @State private var loading: Bool = true
    @State private var error: String? = nil
    @State private var selected: Set<String> = []          // clip ids
    @State private var running: Bool = false
    @State private var resultMessage: String? = nil
    @State private var copiedUnmatched: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if loading {
                loadingState
            } else if let err = error {
                errorState(err)
            } else if let plan = plan {
                planBody(plan)
            }
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 540)
        .onAppear { loadPlan() }
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Backfill historical categories")
                    .font(.title2.weight(.semibold))
                Text("Production clips with no categories will be matched against the imported C4S Historical snapshot.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            if let msg = resultMessage {
                Label(msg, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else if let plan = plan {
                Text("\(selected.count) clip\(selected.count == 1 ? "" : "s") selected of \(plan.exact.count + plan.strong.count + plan.maybe.count) eligible")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel", role: .cancel) { onComplete(nil) }
                .keyboardShortcut(.cancelAction)
            Button {
                runBackfill()
            } label: {
                if running {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Run backfill", systemImage: "arrow.down.doc.fill")
                }
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .disabled(selected.isEmpty || running)
        }
        .padding(16)
    }

    // MARK: - Loading / error states

    private var loadingState: some View {
        VStack(spacing: 10) {
            Spacer()
            ProgressView()
            Text("Building plan…").font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Plan body

    @ViewBuilder
    private func planBody(_ plan: HistoricalCategoryBackfillService.Plan) -> some View {
        if plan.totalTargetClips == 0 {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                Text("Nothing to backfill — every production clip already has categories.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !plan.exact.isEmpty {
                        bucketSection(title: "Exact title match",
                                      systemImage: "checkmark.circle.fill",
                                      tint: .green,
                                      hint: "Same title after normalization (apostrophes / commas stripped). Safe.",
                                      rows: plan.exact)
                    }
                    if !plan.strong.isEmpty {
                        bucketSection(title: "Strong fuzzy match (≥ 0.92)",
                                      systemImage: "checkmark.circle",
                                      tint: .blue,
                                      hint: "Likely the same clip — typo / punctuation drift. Review before running.",
                                      rows: plan.strong)
                    }
                    if !plan.maybe.isEmpty {
                        bucketSection(title: "Maybe (0.75 – 0.92)",
                                      systemImage: "questionmark.circle",
                                      tint: .orange,
                                      hint: "Could be the same clip with a reworded title — eyeball each one.",
                                      rows: plan.maybe)
                    }
                    if !plan.unmatched.isEmpty {
                        unmatchedSection(plan.unmatched)
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: - Bucket section

    private func bucketSection(
        title: String,
        systemImage: String,
        tint: Color,
        hint: String,
        rows: [HistoricalCategoryBackfillService.Candidate]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                Text("(\(rows.count))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                bucketSelectAll(rows: rows)
            }
            Text(hint).font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 6) {
                ForEach(rows) { row in
                    candidateRow(row)
                }
            }
            .padding(10)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func bucketSelectAll(rows: [HistoricalCategoryBackfillService.Candidate]) -> some View {
        let ids = Set(rows.map(\.clipId))
        let allSelected = ids.isSubset(of: selected)
        return Button(allSelected ? "Deselect all" : "Select all") {
            if allSelected { selected.subtract(ids) }
            else { selected.formUnion(ids) }
        }
        .font(.caption)
        .buttonStyle(.borderless)
    }

    // MARK: - Candidate row

    private func candidateRow(_ cand: HistoricalCategoryBackfillService.Candidate) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { selected.contains(cand.clipId) },
                set: { isOn in
                    if isOn { selected.insert(cand.clipId) }
                    else    { selected.remove(cand.clipId) }
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    personaPill(cand.personaCode)
                    Text(cand.clipTitle)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    if cand.kind != .exact {
                        Text(String(format: "%.2f", cand.score))
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(scoreTint(cand.score).opacity(0.18), in: Capsule())
                            .foregroundStyle(scoreTint(cand.score))
                    }
                }

                if cand.kind != .exact {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(cand.c4sTitle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if cand.storeMismatch {
                            Text("(store: \(cand.c4sStore))")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(.orange.opacity(0.2), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // Categories preview
                if cand.categories.isEmpty {
                    Text("(no categories on the matched C4S row)")
                        .font(.caption.italic())
                        .foregroundStyle(.tertiary)
                } else {
                    FlowLayout(spacing: 4) {
                        ForEach(Array(cand.categories.enumerated()), id: \.offset) { i, cat in
                            Text(cat)
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                            if i < min(cand.categories.count - 1, 11) {
                                EmptyView()
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }

    private func personaPill(_ code: String) -> some View {
        Text(code)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(appState.color(forPersona: code).opacity(0.2), in: Capsule())
            .foregroundStyle(appState.color(forPersona: code))
    }

    private func scoreTint(_ score: Double) -> Color {
        if score >= 0.92 { return .blue }
        if score >= 0.75 { return .orange }
        return .red
    }

    // MARK: - Unmatched section

    private func unmatchedSection(_ rows: [HistoricalCategoryBackfillService.UnmatchedClip]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Cannot match", systemImage: "xmark.circle")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text("(\(rows.count))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    let lines = rows.map { "\($0.personaCode)  \($0.clipTitle)" }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
                    withAnimation { copiedUnmatched = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation { copiedUnmatched = false }
                    }
                } label: {
                    Label(copiedUnmatched ? "Copied" : "Copy list",
                          systemImage: copiedUnmatched ? "checkmark" : "doc.on.doc")
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            Text("These clips have no good match in the C4S Historical snapshot. Some may be customs that never went on the storefront, others may have been delisted. Edit categories manually, or skip.")
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        personaPill(row.personaCode)
                        Text(row.clipTitle)
                            .font(.callout)
                            .textSelection(.enabled)
                        Spacer()
                        if let cand = row.bestCandidateTitle {
                            Text("nearest: \(cand)")
                                .font(.caption2.italic())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                            Text(String(format: "%.2f", row.bestScore))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(10)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Actions

    private func loadPlan() {
        loading = true
        error = nil
        Task { @MainActor in
            do {
                let p = try HistoricalCategoryBackfillService.plan()
                plan = p
                // Defaults: every exact + every strong checked. Maybe
                // and unmatched start unchecked. Strong gets a quick
                // sanity-check pass — if the score is exactly the
                // borderline 0.92–0.94 range AND only one character
                // separates the titles, it's often a different person
                // (Thelma/Velma). Keep them checked but flag visually
                // via the score pill — the user can still untick them.
                var defaults = Set<String>()
                defaults.formUnion(p.exact.map(\.clipId))
                defaults.formUnion(p.strong.map(\.clipId))
                selected = defaults
                loading = false
            } catch {
                self.error = error.localizedDescription
                loading = false
            }
        }
    }

    private func runBackfill() {
        guard let plan = plan else { return }
        let chosen = (plan.exact + plan.strong + plan.maybe)
            .filter { selected.contains($0.clipId) }
        guard !chosen.isEmpty else { return }
        running = true
        Task { @MainActor in
            do {
                let n = try DatabaseService.shared.applyHistoricalCategoryBackfill(chosen)
                appState.reloadClips()
                appState.reloadCategories()
                resultMessage = "Backfilled \(n) clip\(n == 1 ? "" : "s")."
                running = false
                // Brief pause so the user sees the success line, then close.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    onComplete(n)
                }
            } catch {
                self.error = "Backfill failed: \(error.localizedDescription)"
                running = false
            }
        }
    }
}
