import SwiftUI
import Charts
import PurpleAtticCore

/// End-to-end monitoring dashboard: numbers, trend charts, and drill-down across the four things
/// worth watching — 3-copy archive health, purge / space reclaimed, new items archived, and the
/// off-site (B2) backup. Reads only the persisted stores via `AppState` (no live engine work), so
/// it's instant and safe to open any time.
struct DashboardView: View {
    @EnvironmentObject var appState: AppState

    private var summary: DashboardMetrics.Summary { appState.dashboardSummary }
    private var runs: [RunRecord] { appState.runHistory }
    private var audits: [PurgeAuditRecord] { appState.purgeAudits }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if runs.isEmpty && audits.isEmpty {
                    emptyState
                } else {
                    archiveHealthCard
                    purgeCard
                    newItemsCard
                    offsiteCard
                }
            }
            .padding(20)
            .textSelection(.enabled)
        }
        .onAppear { appState.refreshDashboard() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis").foregroundStyle(Color(red: 0.55, green: 0.35, blue: 0.95))
                Text("Dashboard").font(.title3.weight(.semibold))
            }
            Spacer()
            scheduleBadge
            Button {
                appState.refreshDashboard()
            } label: { Image(systemName: "arrow.clockwise") }
                .help("Reload from the run history and audit log")
        }
    }

    private var scheduleBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: appState.schedulerLoaded ? "clock.badge.checkmark" : "clock.badge.xmark")
                .foregroundStyle(appState.schedulerLoaded ? .green : .secondary)
            Text(appState.schedulerLoaded ? "Scheduled run active" : "Schedule off")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        Card(title: "No runs recorded yet") {
            Text("Once the scheduled archive runs (or you run one from the Archive pane), its results appear here — verified files, new photos, off-site snapshots, and what's queued for purge. Structured history starts from this version, so the first chart point is the next run.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: 1 — Archive health

    private var archiveHealthCard: some View {
        Card(title: "3-copy archive health") {
            HStack(spacing: 28) {
                stat("Last run", value: relative(summary.lastRunAt),
                     tint: summary.lastRunOK ? .green : .orange,
                     systemImage: summary.lastRunOK ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                stat("Files verified", value: summary.lastVerifiedFileCount.formatted(), tint: .primary)
                stat("Discrepancies", value: summary.lastDiscrepancies.formatted(),
                     tint: summary.lastDiscrepancies == 0 ? .green : .red)
                stat("Runs OK", value: "\(summary.runsOK)/\(summary.runsTotal)", tint: .secondary)
            }
            if let clean = summary.lastCleanVerifyAt {
                Label("Last clean verify (0 discrepancies): \(absolute(clean))", systemImage: "checkmark.shield.fill")
                    .font(.caption).foregroundStyle(.green)
            }

            let series = DashboardMetrics.verifiedFilesSeries(runs)
            if series.count >= 2 {
                Divider()
                Text("Archive size (files verified) over time").font(.caption).foregroundStyle(.secondary)
                Chart(series) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Files", p.value))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", p.date), y: .value("Files", p.value))
                }
                .frame(height: 120)
            }

            recentRunsDrilldown
        }
    }

    private var recentRunsDrilldown: some View {
        DisclosureGroup("Recent runs (\(min(runs.count, 20)) of \(runs.count))") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(runs.suffix(20).reversed()) { r in
                    HStack(spacing: 10) {
                        Image(systemName: r.allSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(r.allSucceeded ? .green : .red).font(.caption)
                        Text(absolute(r.startedAt)).font(.system(.caption, design: .monospaced))
                        Spacer()
                        Text("\(r.metrics.primaryFileCount.formatted()) files")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("+\(r.newItemsArchived) new").font(.caption2).foregroundStyle(.secondary)
                        if r.metrics.verifyDiscrepancies > 0 {
                            Text("\(r.metrics.verifyDiscrepancies) disc.").font(.caption2).foregroundStyle(.red)
                        }
                        Text(r.trigger).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.top, 4)
        }
        .font(.caption)
    }

    // MARK: 2 — Purge / space reclaimed

    private var purgeCard: some View {
        Card(title: "Purge & space reclaimed") {
            HStack(spacing: 28) {
                stat("Ready to purge", value: summary.readyToPurge.formatted(),
                     tint: summary.readyToPurge > 0 ? .orange : .secondary, systemImage: "tray.full")
                stat("Staged (total)", value: summary.totalStaged.formatted(), tint: .secondary)
                stat("Deleted (total)", value: summary.totalDeleted.formatted(), tint: .primary)
                stat("Space reclaimed", value: bytes(summary.bytesReclaimed), tint: .green)
            }

            autoStageStatus

            if summary.readyToPurge > 0 {
                Text("\(summary.readyToPurge.formatted()) verified-deletable photo(s) (\(bytes(summary.readyBytes))) are queued in the latest plan"
                     + (summary.manifestComputedAt.map { ", computed \(relative($0))" } ?? "") + ".")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if summary.readyUnverified > 0 {
                Label("\(summary.readyUnverified.formatted()) eligible photo(s) are NOT yet in ≥2 archive copies — never purged until they are.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }

            let purged = DashboardMetrics.cumulativePurgedSeries(audits)
            if purged.count >= 2 {
                Divider()
                Text("Cumulative photos purged (staged + deleted)").font(.caption).foregroundStyle(.secondary)
                Chart(purged) { p in
                    AreaMark(x: .value("Date", p.date), y: .value("Photos", p.value))
                        .foregroundStyle(.orange.opacity(0.25))
                    LineMark(x: .value("Date", p.date), y: .value("Photos", p.value))
                        .foregroundStyle(.orange)
                }
                .frame(height: 110)
            }

            purgeAuditDrilldown
        }
    }

    private var autoStageStatus: some View {
        let p = appState.store.profile
        let on = p.purgeEnabled && p.purgeAutoStage
        return Label(
            on ? "Auto-stage is ON — each night the verified set is added to “\(AppState.toDeleteAlbumName)” automatically."
               : (p.purgeEnabled ? "Auto-stage is OFF — the nightly run plans the purge but stages nothing. Turn it on in the Purge pane."
                                 : "Purge is OFF — no plan is computed. Enable it in the Purge pane."),
            systemImage: on ? "bolt.badge.automatic.fill" : "bolt.slash")
            .font(.caption)
            .foregroundStyle(on ? .green : .secondary)
    }

    private var purgeAuditDrilldown: some View {
        Group {
            if audits.isEmpty {
                EmptyView()
            } else {
                DisclosureGroup("Purge history (\(min(audits.count, 20)) of \(audits.count))") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(audits.suffix(20).reversed()) { a in
                            HStack(spacing: 10) {
                                Image(systemName: a.action == .delete ? "trash.fill" : "rectangle.stack.badge.minus")
                                    .foregroundStyle(a.action == .delete ? .red : .orange).font(.caption)
                                Text(absolute(a.timestamp)).font(.system(.caption, design: .monospaced))
                                Spacer()
                                Text("\(a.succeeded) \(a.action == .delete ? "deleted" : "staged")")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(a.trigger.rawValue).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }
        }
    }

    // MARK: 3 — New items archived

    private var newItemsCard: some View {
        Card(title: "New items archived") {
            HStack(spacing: 28) {
                stat("Total since history began", value: summary.totalNewArchived.formatted(), tint: .primary)
                stat("Recorded runs", value: summary.runsTotal.formatted(), tint: .secondary)
            }
            let series = DashboardMetrics.newItemsSeries(runs).filter { $0.value > 0 }
            if series.count >= 1 {
                Divider()
                Text("New photos captured per run").font(.caption).foregroundStyle(.secondary)
                Chart(series) { p in
                    BarMark(x: .value("Date", p.date, unit: .day), y: .value("New", p.value))
                        .foregroundStyle(Color(red: 0.55, green: 0.35, blue: 0.95))
                }
                .frame(height: 110)
            } else {
                Text("No new items recorded yet — incremental runs that add photos will chart here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 4 — Off-site (B2)

    private var offsiteCard: some View {
        Card(title: "Off-site backup (Backblaze B2)") {
            HStack(spacing: 28) {
                stat("Last snapshot", value: summary.lastSnapshot ?? "—", tint: .secondary)
                stat("Last check", value: checkText(summary.lastCloudCheckOK),
                     tint: cloudTint(summary.lastCloudCheckOK),
                     systemImage: summary.lastCloudCheckOK == true ? "checkmark.seal.fill" : "questionmark.circle")
                stat("Uploaded (total)", value: bytes(summary.totalCloudBytesAdded), tint: .primary)
            }
            if let at = summary.lastCloudAt {
                Text("Last off-site push: \(relative(at)).").font(.caption).foregroundStyle(.secondary)
            }
            let series = DashboardMetrics.cloudBytesSeries(runs)
            if series.count >= 2 {
                Divider()
                Text("Off-site bytes added per run").font(.caption).foregroundStyle(.secondary)
                Chart(series) { p in
                    BarMark(x: .value("Date", p.date, unit: .day), y: .value("Bytes", p.value))
                        .foregroundStyle(.teal)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .binary))
                            }
                        }
                    }
                }
                .frame(height: 110)
            }
        }
    }

    // MARK: Helpers

    private func stat(_ label: String, value: String, tint: Color, systemImage: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage).foregroundStyle(tint).font(.caption) }
                Text(value).font(.title3.weight(.semibold)).foregroundStyle(tint).lineLimit(1)
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func checkText(_ ok: Bool?) -> String {
        switch ok { case .some(true): return "OK"; case .some(false): return "FAILED"; case .none: return "—" }
    }
    private func cloudTint(_ ok: Bool?) -> Color {
        switch ok { case .some(true): return .green; case .some(false): return .red; case .none: return .secondary }
    }
    private func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
    private func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
    private func absolute(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d, HH:mm"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
